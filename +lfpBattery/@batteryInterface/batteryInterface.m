classdef (Abstract) batteryInterface < handle
    %BATTERYINTERFACE: Abstract class / interface for creating battery
    %models.
    
    properties
        maxIterations = uint32(1e3); % maximum number of iterations
        pTol = 1e-6; % tolerance for power iteration
        sTol = 1e-6; % tolerance for SoC limitation iteration
        iTol = 1e-6; % tolerance for current limitation iteration
    end
    properties (SetAccess = 'immutable')
        Cn; % Nominal (or average) capacity in Ah
        Vn; % Nominal (or average) voltage in V
        eta_bc; % efficiency when charging [0,..,1]
        eta_bd; % efficiency when discharging [0,..,1]
    end
    properties (Dependent)
        Cbu; % Useable capacity in Ah
        socMax; % Max SoC (default: 1)
        socMin; % Min SoC (default: 0.2)
        psd; % self discharge rate in 1/month [0,..,1] (default: 0)
    end
    properties (Dependent, SetAccess = 'protected')
        SoC; % State of charge [0,..,1]
    end
    properties (SetAccess = 'protected')
        Cd; % Discharge capacity in Ah (Cd = 0 if SoC = 1)
        SoH; % State of health [0,..,1]
        V; % Resting voltage / V
        Imax = 0; % maximum current in A (determined from cell discharge curves)
    end
    properties %(Access = 'protected')
        soh0; % Last state of health
        cyc; % cycleCounter object
        ageModel; % batteryAgeModel object
        soc_max; % internal soc_max is lower than external socMax if SoH < 1
        soc_min;
        CnMax; % maximum discharge capacity
        CnMin; % minimum discharge capacity
        slTF = false; % true/false variable for limitation of SoC in recursive iteration
        pct = uint32(0); % counter for power iteration
        sct = uint32(0); % counter for soc limiting iteration
        lastPr = 0; % last power request (for handling powerIteration through recursion)
        reH; % function handle: @gt for charging and @lt for discharging
        socLim; % SoC to limit charging/discharging to (depending on charging or discharging)
        hl; % property listener (observer) for ageModel SoH
        sl; % property listener (observer) for soc
        Psd; % self-discharge energy in W
    end
    properties (SetObservable, Hidden, SetAccess = 'protected')
        soc; % State of charge (for internal handling)
    end
    methods
        function b = batteryInterface(varargin)
            %% parse optional inputs
            p = lfpBattery.batteryInterface.parseInputs(varargin{:});
            
            b.SoH = 1;
            b.Cn = p.Results.Cn;
            b.socMin = p.Results.socMin;
            b.socMax = p.Results.socMax;
            b.soc = p.Results.socIni;
            b.CnMax = (1 - b.socMin) .* b.Cn;
            b.CnMin = (1 - b.socMax) .* b.Cn;
            b.Cd = (1 - b.SoC) .* b.Cn;
            b.Vn = 3; % MTODO: Set init nominal voltage with inputParsers or according to dischargeCurves for cell
            b.V = b.Vn; % MTODO: Set init voltage according to discharge capacity and nominal current
            b.eta_bc = 0.97;
            b.eta_bd = 0.97;
                        
            % initialize age model
            warning('off', 'all')
            b.initAgeModel(varargin{:})
            warning('on', 'all')
            
        end % constructor
        function dischargeFit(b, V, C_dis, I, Temp, varargin)
            %DISCHARGEFIT: Uses Levenberg-Marquardt algorithm to fit a
            %discharge curve of a lithium-ion battery in three parts:
            %1: exponential drop at the beginning of the discharge curve
            %2: according to the nernst-equation
            %3: exponential drop at the end of the discharge curve
            %and adds the fitted curve to the battery model b.
            %Syntax:
            %   b.dischargeFit(V, C_dis, I, T);
            %           --> initialization of curve fit params with zeros
            %
            %   b.dischargeFit(V, C_dis, I, T, 'OptionName', 'OptionValue');
            %           --> custom initialization of curve fit params
            %
            %Input arguments:
            %   V:              Voltage (V) = f(C_dis) (from data sheet)
            %   C_dis:          Discharge capacity (Ah) (from data sheet)
            %   I:              Current at which curve was measured
            %   T:              Temperature (K) at which curve was mearured
            %
            %OptionName-OptionValue pairs:
            %
            %   'x0'            Initial params for fit functions.
            %                   default: zeros(9, 1)
            %
            %   x0 = [E0; Ea; Eb; Aex; Bex; Cex; x0; v0; delta] with:
            %
            %   E0, Ea, Eb:     Parameters for Nernst fit (initial estimations)
            %   Aex, Bex, Cex:  Parameters for fit of exponential drop at
            %                   the end of the curve (initial estimations)
            %   x0, v0, delta:  Parameters for fit of exponential drop at
            %                   the beginning of the curve (initial estimations)
            %
            %   'mode'          Function used for fitting curves
            %                   'lsq'           - lsqcurvefit
            %                   'fmin'          - fminsearch
            %                   'both'          - (default) a combination (lsq, then fmin)
            
            % add a new dischargeFit object according to the input arguments
            b.adddfit(lfpBattery.dischargeFit(V, C_dis, I, Temp, varargin{:}));
        end
        function initAgeModel(b, varargin)
            %INITAGEMODEL
            p = lfpBattery.batteryInterface.parseInputs(varargin{:});
            if ~isempty(b.hl)
                delete(b.hl)
            end
            if ~strcmp(p.Results.ageModel, 'none')
                if strcmp(p.Results.cycleCounter, 'auto')
                    cy = lfpBattery.dambrowskiCounter(b.soc, b.soc_max);
                else
                    cy = p.Results.cycleCounter;
                    cy.socMax = b.soc_max;
                end
                b.cyc = cy;
                if strcmp(p.Results.ageModel, 'EO')
                    b.ageModel = lfpBattery.eoAgeModel(cy);
                else
                    b.ageModel = p.Results.ageModel;
                    b.addCounter(b.cyc)
                end
                % Make sure the battery model's SoH is updated every time
                % the age model's SoH changes.
                b.hl = addlistener(b.ageModel, 'SoH', 'PostSet', @b.updateSoH);
            else
                b.cyc = lfpBattery.dummyCycleCounter;
                b.ageModel = lfpBattery.dummyAgeModel;
            end
        end % initAgeModel
        function addCounter(b, cy)
            %ADDCOUNTER: MTODO: Doc
            if ~isempty(b.sl)
                delete(b.sl)
            end
            % Make sure the cycleCounter's lUpdate method is called
            % every time the soc property changes.
            b.sl = addlistener(b, 'soc', 'PostSet', @cy.lUpdate);
            b.ageModel.addCounter(cy);
        end
        %% setters
        function set.socMin(b, s)
            assert(s >= 0 && s <= 1, 'socMin must be between 0 and 1')
            if s == 0
                b.soc_min = eps;
            else
                b.soc_min = s;
            end
        end
        function set.socMax(b, s)
            assert(s <= 1, 'soc_max cannot be greater than 1')
            assert(s > b.socMin, 'soc_max cannot be smaller than or equal to soc_min')
            % Limit socMax by SoH
            b.soc_max = s .* b.SoH;
            b.cyc.socMax = s .* b.SoH;
        end
        function set.maxIterations(b, n)
            b.maxIterations = uint32(max(1, n));
        end
        function set.pTol(b, tol)
            b.pTol = abs(tol);
        end
        function set.sTol(b, tol)
            b.sTol = abs(tol);
        end
        function set.iTol(b, tol)
            b.iTol = abs(tol);
        end
        function set.psd(b, p)
           lfpBattery.commons.onezeroChk(p, 'self-discharge rate')
           b.Psd = p .* 1/(365.25.*86400./12) .* b.Cn ./ 3600 .* b.Vn; % 1/(month in seconds) * As * V = W
        end
        %% getters
        function a = get.SoC(b)
            s = b.soc ./ b.SoH; % SoC according to max capacity
            a = lfpBattery.commons.upperlowerlim(s, 0, b.socMax);
        end
        function a = get.Cbu(b) % useable capacity after aging
            a = (b.soc_max - b.soc_min) .* b.Cn;
        end
        function a = get.socMax(b)
            a = b.soc_max ./ b.SoH;
        end
        function a = get.socMin(b)
            a = b.soc_min;
            if a == eps
                a = 0;
            end
        end
    end % public methods
    
    methods (Access = 'protected')
        function updateSoH(b, ~, event)
            maxSoC = b.socMax; % save last socMax
            b.SoH = event.AffectedObject.SoH;
            b.socMax = maxSoC; % update socMax (updated automatically in setter)
        end
    end
    
    methods (Static, Access = 'protected')
        function p = parseInputs(varargin)
            Cn_default = 3.5; % MTODO: remove default value
            p = inputParser;
            addOptional(p, 'Cn', Cn_default, @isnumeric)
            addOptional(p, 'socMin', 0.2, @isnumeric)
            addOptional(p, 'socMax', 1, @isnumeric)
            addOptional(p, 'socIni', 0.2, @(x) x >= 0 && x <= 1)
            validModels = {'auto'};
            type = 'lfpBattery.cycleCounter';
            addOptional(p, 'cycleCounter', 'auto', ...
                @(x) lfpBattery.batteryInterface.validateAM(x, validModels, type))
            validModels = {'none', 'EO'};
            type = 'lfpBattery.batteryAgeModel';
            addOptional(p, 'ageModel', 'none', ...
                @(x) lfpBattery.batteryInterface.validateAM(x, validModels, type))
            parse(p, varargin{:});
        end
        function tf = validateAM(x, validModels, type)
            % validates age model & cycle counter inputs
            if ischar(x)
                tf = any(validatestring(x, validModels));
            else
                tf = lfpBattery.commons.itfcmp(x, type);
            end
        end
    end
    
    methods (Abstract)
        % POWERREQUEST: MTODO: Doc
        % P:  power in W
        % dt: size of time step in S
        P = powerRequest(b, P, dt);
        addcurves(b, d, type); % adds a collection of discharge curves
        %ITERATEPOWER: Iteration to determine new state given a certain power.
        % The state of the battery is not changed by this method.
        % Syntax: [P, Cd, V, soc] = b.iteratePower(P, dt);
        %
        % Input arguments:
        % b      -   Subclass of the batteryInterface (object calling the method)
        % P      -   Requested charge or discharge power in W
        % dt     -   Simulation time step size in s
        %
        % Output arguments:
        % P      -   Actual charge or discharge power in W
        % Cd     -   Discharge capacity of the battery in Ah
        % V      -   Resting voltage in V
        % soc    -   State of charge [0,..,1]
        [P, Cd, V, soc] = iteratePower(b, P, dt, reH, socLim, sd);
    end % abstract methods
    
    methods (Abstract, Access = 'protected')
        findImax(b); % determins the maximum current according to the discharge curves
    end
end


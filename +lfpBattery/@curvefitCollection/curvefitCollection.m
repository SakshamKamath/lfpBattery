classdef curvefitCollection < lfpBattery.sortedFunctions
    %CURVEFITCOLLECTION sorted collection of curveFit objects. Uses
    %interplation to extract data between two curve fits according to z
    %value
    %
    %curvefitCollection Properties:
    %
    %   xydata - curve fit objects (should implement curveFitInterface)
    %   z      - z data at which the respective curve measurements were
    %            recorded (i. e. temperature, current,...)
    %
    %
    %Authors: Marc Jakobi, Festus Anyangbe, Marc Schmidt
    %         January 2017
    
    properties (Abstract)
        interpMethod; % Method for interpolation
    end
    properties (Access = 'protected')
        y; % Initialization of curve fit results that will be interpolated in iterp method.
    end
    
    methods
        function c = curvefitCollection(varargin)
            c@lfpBattery.sortedFunctions(varargin{:})
        end
        function y = interp(c, z, x)
            %INTERP returns interpolated result between calculations of
            %multiple curveFits.
            %Syntax: y = INTERP(z, x)
            feval(c.errHandler, c); % make sure there are enough functions in the collection
            for i = 1:numel(c.y)
                cfit = c.xydata(i); % extract curve fit pointer
                c.y(i) = cfit(x);
            end
            % interpolate 
              y = interp1(c.z, c.y, z, c.interpMethod, 'extrap');
              % uncomment below to limit to curve fits
%             y = lfpBattery.commons.upperlowerlim(...
%                 interp1(c.z, c.y, z, c.interpMethod, 'extrap'), ...
%                 min(c.y), max(c.y)); 
        end
        
        function add(c, d)
           c.validateInputInterface(d);
           c.add@lfpBattery.sortedFunctions(d);
           c.y = zeros(size(c.z));
        end
        function remove(c, z)
            c.remove@lfpBattery.sortedFunctions(z);
            c.y = zeros(size(c.z));
        end
        function plotResults(c, varargin)
            %PLOTRESULTS: Compares scatters of the raw data with the fits
            %in a figure window.
            %PLOTRESULTS('OptionName', 'OptionValue') plots results
            %with additional options.
            %
            %Options:
            %   noRawData (logical) - don't scatter raw data (default: false)
            %   noFitData (logical) - don't scatter fit data (default: false)
            figure;
            hold on
            tmp = c.xydata(1);
            plotResults(tmp, false, varargin{:});
            if nargin < 3
                legend('raw data', 'fits', 'Location', 'Best')
            end
            grid on
            for i = 2:numel(c.xydata)
                tmp = c.xydata(i);
                plotResults(tmp, false, varargin{:});
            end
        end
    end
    methods (Static)
        function validateInputInterface(obj)
            lfpBattery.commons.validateInterface(obj, 'lfpBattery.curveFitInterface');
        end
    end
end

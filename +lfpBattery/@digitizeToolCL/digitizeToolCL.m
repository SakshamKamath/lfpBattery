classdef digitizeToolCL < lfpBattery.digitizeToolState
    %DIGITIZETOOLCL digitizeTool State object for cycle life curve
    %digitizing and fitting.
    %
    %Authors: Marc Jakobi, Festus Anyangbe, Marc Schmidt
    %         February 2017
    %
    %SEE ALSO: lfpBattery.digitizeTool lfpBattery.digitizeToolState
    %lfpBattery.digitizeToolDC lfpBattery.digitizeToolCCCV
    
    properties
        xLabel = 'depth of discharge';
        yLabel = 'cycles to failure';
    end
    properties (Dependent, SetAccess = 'protected')
        numsets;
        I;
        T;
    end
    
    methods
        function obj = digitizeToolCL(varargin)
            obj@lfpBattery.digitizeToolState(varargin{:})
        end
        function chk = getYAxisYdata(obj)
            chk = getYAxisYdata@lfpBattery.digitizeToolState(obj);
            % Determine Y-axis scaling
            Ytype = questdlg(['Axis scaling (', obj.yLabel,')'], ...
                'Walkthrough', ...
                'LINEAR', 'LOGARITHMIC', 'CANCEL', 'LINEAR');
            drawnow
            switch Ytype
                case 'LINEAR'
                    obj.scalefactorYdata = obj.YAxisYdata - obj.OriginXYdata(2);
                case 'LOGARITHMIC'
                    obj.logy = true;
                    obj.scalefactorYdata = log10(obj.YAxisYdata / obj.OriginXYdata(2));
                case 'CANCEL'
                    obj.dTool.errCt = 7;
                    error('cancelled')
            end
        end % getYAxisYdata
        function n = get.numsets(obj) %#ok<MANU>
            n = 1;
        end
        function i = get.I(obj) %#ok<MANU>
            i = [];
        end
        function t = get.T(obj) %#ok<MANU>
            t = [];
        end
        function f = createFit(obj, ~)
            import lfpBattery.*
            f = woehlerFit(obj.dTool.ImgData(1).x, obj.dTool.ImgData(1).y); %(N, DoD)
        end
        function plotResults(obj)
            obj.dTool.fit.plotResults(true)
        end
    end
    
end


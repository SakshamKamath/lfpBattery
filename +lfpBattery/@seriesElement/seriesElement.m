classdef (Abstract) seriesElement < lfpBattery.batCircuitElement
    %SERIESELEMENT Summary of this class goes here
    %   Detailed explanation goes here

    properties (Dependent, SetAccess = 'immutable')
        Zi;
    end
    
    methods
        function b = seriesElement(varargin)
            b@lfpBattery.batCircuitElement(varargin{:})
        end
        function v = getNewVoltage(b, I, dt)
            v = sum(arrayfun(@(x) getNewVoltage(x, I, dt), b.El));
        end
        function z = get.Zi(b)
            z = sum([b.El.Zi]);
        end
    end
    
    methods (Access = 'protected')
        function i = findImax(b)
            i = min(findImax@lfpBattery.batCircuitElement(b));
            b.Imax = i;
        end
        function p = getZProportions(b)
            % lowest impedance --> lowest voltage
            zv = [b.El.Zi]; % vector of internal impedances
            p = zv ./ sum(zv);
        end
    end
    
end

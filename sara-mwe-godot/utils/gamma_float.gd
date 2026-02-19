## Container for values with non-linear transfer curves.
##
## Stores a base float and a gamma exponent. Useful for parameters 
## like brush hardness or flow where linear sliders feel unnatural.
class_name GammaFloat

var _value: float = 0.0
var _gamma: float = 1.0


func _init(__property: float, __gamma: float = 1.0) -> void:
    self._value = __property
    self._gamma = __gamma

## get _gamma
func gamma() -> float:
    return _gamma

## get inverted _gamma
func gamma_inv() -> float:
    return 1.0 / _gamma

## get float value
func raw() -> float:
    return _value


## _gamma applied
func transf() -> float:
    return pow(_value, _gamma)


## inversion _gamma applied
func transf_inv() -> float:
    return pow(_value, 1.0 / _gamma)


func _to_string() -> String:
    return "_gammaFloat(%.2f, %.2f)" % [_value, _gamma]


## checks if _gammas are the same
func equal__gamma(other) -> bool:
    if other is GammaFloat:
        if _gamma != other.gamma():
            push_error("_gammaFloat different _gammas: %.2f vs %.2f" % [_gamma, other.gamma()])
        return true
    return false

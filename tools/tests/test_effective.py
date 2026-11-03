from autochess_tools.effective import Estimate, interpolate, samples


def test_interpolate_between_points() -> None:
    curve = [(1, 0.0), (2, 0.4), (3, 0.8)]
    assert interpolate(curve, 0.6) == Estimate(2.5)


def test_interpolate_saturated_curve_is_a_lower_bound() -> None:
    curve = [(1, 0.2), (2, 0.9), (3, 1.0), (4, 1.0)]
    assert interpolate(curve, 1.0) == Estimate(3, at_least=True)
    assert str(interpolate(curve, 1.0)) == "≥3"


def test_interpolate_below_curve_returns_first_point() -> None:
    assert interpolate([(1, 0.3), (2, 0.6)], 0.1) == Estimate(1)


def test_samples_are_reproducible() -> None:
    assert samples(["a", "b", "c"], 50, seed=1) == samples(["a", "b", "c"], 50, seed=1)
    assert samples(["a", "b", "c"], 50, seed=1) != samples(["a", "b", "c"], 50, seed=2)

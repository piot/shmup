#![api]

struct Prnd

impl Prnd {
    /// Returns a random value between min and max inclusively
    fn random_range_int(value: Int, min: Int, max: Int) -> Int {
        min + value.rnd().mod_euclid(max - min + 1)
    }
}

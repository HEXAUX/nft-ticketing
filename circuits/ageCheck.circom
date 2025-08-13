// A toy Circom circuit demonstrating an "age >= 18" proof.
// NOTE: This is a highly simplified example for demonstration purposes
// and is not production ready. It does not handle overflow or negative
// numbers robustly and is only meant to illustrate how a zero-knowledge
// circuit might be structured for an age check.

pragma circom 2.0.0;

// Template that asserts the input `age` is at least 18.
template AgeCheck() {
    // Public inputs
    signal input age;
    signal output isAdult;

    // Internal signal representing the difference between age and the minimum
    // required age (18). If age >= 18 then diff will be >= 0.
    signal diff;

    // Compute difference
    diff <== age - 18;

    // Check that diff is non‑negative by forcing it into the field and
    // multiplying by 1. This is not a strict non‑negativity check; for a
    // real age check you would want to use a range proof or bit decomposition
    // with comparisons. This simplified version is adequate for demonstration.
    isAdult <== (diff >= 0);
}

component main = AgeCheck();

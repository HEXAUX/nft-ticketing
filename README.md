## Circuits

This directory contains example Circom circuits illustrating how
zero‑knowledge proofs can enforce properties on user data without
revealing sensitive information. The circuits here are **not** meant
for production use; they are simplified proof‑of‑concepts.

### ageCheck.circom

The `ageCheck.circom` circuit demonstrates a very simple proof that
a user is at least 18 years old. It defines a template `AgeCheck` that
takes an `age` input and outputs a boolean `isAdult`. The circuit
computes the difference `age - 18` and uses that to determine whether
the user meets the minimum age requirement. In a real implementation
you would not reveal the user's exact age; instead you would use a
range proof or bit decomposition along with a proper comparator to
assert that `age >= 18` without disclosing the input. Negative values
and overflows would also need to be handled.

To compile the circuit with Circom you can run:

    circom ageCheck.circom --r1cs --wasm --sym

This will generate the artifacts needed to produce a proof and a
verifier contract. In this repository we focus on the Solidity
integration rather than the full ZK workflow.
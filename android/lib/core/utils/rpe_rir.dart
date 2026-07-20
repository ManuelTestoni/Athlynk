/// RPE ↔ RIR conversion used by the coach plan builder's unification prompt.
/// Same approximation as iOS/web: `RPE ≈ 10 − RIR`, `RIR ≈ 10 − RPE`,
/// clamped to the meaningful 0–10 band.
double rpeFromRir(double rir) => (10 - rir).clamp(0, 10).toDouble();

double rirFromRpe(double rpe) => (10 - rpe).clamp(0, 10).toDouble();

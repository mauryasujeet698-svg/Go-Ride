export const rideStatuses = [
  "REQUESTED",
  "SEARCHING",
  "DRIVER_ASSIGNED",
  "DRIVER_ARRIVING",
  "DRIVER_ARRIVED",
  "IN_PROGRESS",
  "COMPLETED",
  "CANCELLED",
  "EXPIRED",
  "NO_DRIVER_FOUND",
  "FAILED"
] as const;

export type RideStatus = (typeof rideStatuses)[number];

const transitions: Readonly<Record<RideStatus, readonly RideStatus[]>> = {
  REQUESTED: ["SEARCHING", "CANCELLED", "FAILED"],
  SEARCHING: ["DRIVER_ASSIGNED", "CANCELLED", "EXPIRED", "NO_DRIVER_FOUND", "FAILED"],
  DRIVER_ASSIGNED: ["DRIVER_ARRIVING", "CANCELLED", "FAILED"],
  DRIVER_ARRIVING: ["DRIVER_ARRIVED", "CANCELLED", "FAILED"],
  DRIVER_ARRIVED: ["IN_PROGRESS", "CANCELLED", "FAILED"],
  IN_PROGRESS: ["COMPLETED", "FAILED"],
  COMPLETED: [],
  CANCELLED: [],
  EXPIRED: [],
  NO_DRIVER_FOUND: [],
  FAILED: []
};

export function canTransition(from: RideStatus, to: RideStatus): boolean {
  return from === to || transitions[from].includes(to);
}

export function assertTransition(from: RideStatus, to: RideStatus): void {
  if (!canTransition(from, to)) {
    throw new Error(`Invalid ride transition: ${from} -> ${to}`);
  }
}

export function isTerminal(status: RideStatus): boolean {
  return transitions[status].length === 0;
}

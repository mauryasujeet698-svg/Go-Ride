export type CoordinateInput = { latitude: number; longitude: number };
export type RoadRoute = {
 distanceMeters: number;
 durationSeconds: number;
 geometry: CoordinateInput[];
 provider: string;
 calculatedAt: string;
};
export interface RoutingProvider {
 readonly name: string;
 getRoute(origin: CoordinateInput, destination: CoordinateInput): Promise<RoadRoute>;
}

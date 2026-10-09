import "dotenv/config";
import { buildServer } from "./server.js";

async function main(): Promise<void> {
 const { app, host, port } = await buildServer();
 await app.listen({ host, port });
}
main().catch((error: unknown) => {
 process.stderr.write("Go-Ride API failed to start: " + (error instanceof Error ? error.message : "unknown error") + "\n");
 process.exitCode = 1;
});

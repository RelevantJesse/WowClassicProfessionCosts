# Repository Guidelines

## Project Structure & Module Organization

- `src/WowAhPlanner.Core`: Domain models, planner algorithm, and port interfaces (no EF Core / ASP.NET dependencies).
- `src/WowAhPlanner.Infrastructure`: SQLite EF Core persistence, caching, price providers, data pack loader, background workers.
- `src/WowAhPlanner.WinForms`: WinForms desktop UI (composition root/DI, local state, page controls).
- `tests/WowAhPlanner.Tests`: Unit tests (xUnit).
- `data/{GameVersion}/`: Versioned data packs (e.g. `data/Anniversary/items.json`, `data/Anniversary/professions/tailoring.json`, `data/Anniversary/producers.json`).
- `addon/ProfessionLevelerScan`: In-game scan addon that exports price snapshots.
- `docs/`: Notes, UX decisions, and status docs.
- `tools/`: Utilities/scripts.

## Build, Test, and Development Commands

- `dotnet build WowAhPlanner.slnx` - build the solution.
- `dotnet test` - run all unit tests.
- `dotnet run --project src/WowAhPlanner.WinForms` - run the WinForms app locally.

If Debug builds fail due to locked DLLs, stop the running web process or build with `-c Release`.

## Coding Style & Naming Conventions

- C#: 4-space indentation; use standard .NET naming (`PascalCase` types/methods, `camelCase` locals/params).
- Keep boundaries strict: Core must not reference UI/Infrastructure. Add dependencies via ports in `WowAhPlanner.Core.Ports` and implement them in Infrastructure. UIs (WinForms/Web) reference Core + Infrastructure.
- JSON data packs: keep small and version-scoped; prefer stable identifiers (`recipeId`, `producerId`, `itemId`) and consistent casing.

## Testing Guidelines

- Framework: xUnit (`[Fact]`).
- Prefer deterministic tests: stub providers/repositories; avoid time and filesystem dependencies unless the test is explicitly for loaders.
- Naming: `*Tests.cs` with behavior-focused method names.

## Commit & Pull Request Guidelines

- Commit messages are short and imperative (examples from history: `Fix exact search`, `Vendor item support`, `Docs update`).
- PRs should include: what/why, how to validate (especially for `data/` and `addon/` changes), and screenshots for UI changes when applicable.

## Configuration & Safety Notes

- Do not commit secrets or API keys.
- WinForms stores local app data under `%LOCALAPPDATA%\WowAhPlanner` (SQLite + JSON state).
- Treat uploaded snapshots as untrusted input: validate schema and realm/version metadata; fail closed with clear errors.

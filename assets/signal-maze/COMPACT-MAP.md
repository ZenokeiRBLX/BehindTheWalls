# Signal Maze

Built in the Studio place `Map Creation` (`126262358232325`) as `Workspace.SignalMaze`.

The map occupies approximately 112 x 112 studs around `(147, 0, 54)`. Start at `MazeEntrance`: the TV corridor opens into a signal court, with west and east side chambers, a northern loop, a receiver chamber, and a blind alcove. The receiver is a visual destination; it has no scripted objective or exit behavior.

The build uses the existing Wall_1 and Wall_2 meshes, their nine bones per mesh, the existing flesh material, and the existing TV housing and broadcast atlas. It contains 98 anchored parts, 28 TVs, 153 bones, and 13 lights without shadows. Decorative meshes do not collide; simple invisible boxes provide wall collision. No runtime scripts or particle emitters are added.

The original walls, baseplates, spawn, and lighting children are preserved in `ServerStorage.SignalMaze_Backup`. Original lighting properties and camera position are attributes on that folder.

For an overhead layout view, temporarily hide `Architecture.Ceiling_RemoveForLayoutView` in Studio and restore it afterward.

`build-studio-map.luau` is a one-time Studio edit-mode construction recipe, not a runtime script or Rojo-mounted asset. It refuses to run when the map or its backup already exists.

Validation: all seven route targets were reachable from the entrance on a two-stud sampling grid with 1.8-stud horizontal agent clearance; all 1,598 walkable samples belonged to the same connected region. This is a geometric clearance check, not an avatar playtest or performance benchmark. The entrance was inspected through Studio screenshots, and shadow visibility was increased after review.

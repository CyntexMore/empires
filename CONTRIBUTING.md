# Contributing to Empires

Thank you for your interest in contributing to Empires! We appreciate your time and effort in helping improve this project.

## Code of Conduct

Please be respectful and constructive in all interactions with the project and its community.

## Getting Started

Before contributing, make sure you can build and run the project:

```bash
nix develop
zig build -Dtarget=native
./zig-out/bin/empires
```

## Commit Message Guidelines

All commits **MUST** follow the [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/) specification.

### Commit Format

```
<type>[optional scope]: <description>

[optional body]

[optional footer(s)]
```

### Types

- `feat:` - A new feature
- `fix:` - A bug fix
- `docs:` - Documentation only changes
- `style:` - Code style changes (formatting, missing semicolons, etc.)
- `refactor:` - Code changes that neither fix a bug nor add a feature
- `perf:` - Performance improvements
- `test:` - Adding or correcting tests
- `chore:` - Maintenance tasks (dependencies, build configuration, etc.)
- `ci:` - CI/CD configuration changes

### Examples

```
feat: add unit selection with mouse drag

fix(renderer): correct texture scaling on high DPI displays

docs: update building instructions for Windows

chore: add MIT license
```

### Breaking Changes

If your commit introduces a breaking change, add `!` after the type or include `BREAKING CHANGE:` in the footer:

```
feat!: change resource system API

BREAKING CHANGE: Resource loading now requires explicit initialization
```

## Dependency Management

Do not add unnecessary dependencies to this project.

Before adding any new dependency:

1. Consider if the functionality can be reasonably implemented in-house
2. Evaluate the dependency's maintenance status, license compatibility, and size
3. Discuss the addition in an issue before submitting a pull request
4. Provide clear justification for why the dependency is needed

We prefer a lean dependency tree to keep the project maintainable and easy to build.

## Licensing

### Source Code

All source code contributions will be licensed under **GPL-v3**. By submitting code to this project, you agree to license your contributions under the GPL-v3 license.

Your contributions must be your own original work or properly attributed with compatible licensing.

### Textures and Assets

All texture and asset contributions **MUST** be licensed under **CC BY 4.0** (Creative Commons Attribution 4.0 International).

For each texture file you contribute, you must include a corresponding `.LICENSE` file. For example:

```
resources/textures/icons/my_icon.png
resources/textures/icons/my_icon.png.LICENSE
```

See [resources/textures/icons/gold\_icon.png.LICENSE](resources/textures/icons/gold_icon.png.LICENSE) for an example.

The `.LICENSE` file should contain:

```
Author: <Your Name>
Contact: <Your Email>
```

Contributions with improperly licensed assets will not be accepted.

## Pull Request Process

1. Fork the repository and create your own branch from the appropriate branch
2. Ensure your code builds without warnings: `zig build`
3. Write clear, self-documenting code following the existing style
4. Use Conventional Commits for all commit messages
5. Submit your pull request with a clear description of the changes

## Questions?

If you have questions about contributing, feel free to open an issue for discussion.

---

Thank you for contributing to Empires!


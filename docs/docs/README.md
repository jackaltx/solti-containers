# solti-containers/docs - Development Documentation

> **Patterns, Architectures, and Development Guides**
> *Comprehensive technical documentation for the solti-containers collection, covering patterns, decisions, and development workflows.*

## Purpose

This directory contains technical documentation, architectural decisions, development patterns, and sprint reports for the solti-containers Ansible collection.

## Document Categories

### Architecture & Design Patterns

#### [Container-Role-Architecture.md](Container-Role-Architecture.md)

Complete architecture guide for the solti-containers pattern.

**For:** Developers (human)
**Topics:**

- _base role design
- Service role structure
- Quadlet integration patterns
- systemd service management

#### [Solti-Container-Pattern.md](Solti-Container-Pattern.md)

The standardized SOLTI container deployment pattern.

**For:** Developers (human)
**Topics:**

- Consistent role structure
- Common variables
- Deployment workflow
- Best practices

#### [Container-Mount-Options.md](Container-Mount-Options.md)

Container volume mounting strategies and options.

**For:** Developers (reference)
**Topics:**

- Volume mount types
- SELinux contexts
- Performance considerations
- Security implications

#### [Podman-User-Namespaces.md](Podman-User-Namespaces.md)

Podman user namespace configuration and troubleshooting.

**For:** Developers (technical reference)
**Topics:**

- User namespace mapping
- UID/GID considerations
- File ownership issues
- Troubleshooting techniques

### Technical Decisions

#### [TLS-Architecture-Decision.md](TLS-Architecture-Decision.md)

Decision record for TLS/SSL architecture using Traefik.

**For:** Developers and architects (human)
**Topics:**

- Why Traefik was chosen
- SSL termination strategy
- Certificate management
- Trade-offs considered

### Development Workflows

#### [Check-Upgrade-Pattern.md](Check-Upgrade-Pattern.md)

Pattern for implementing service upgrade checks.

**For:** Developers (implementation guide)
**Topics:**

- Version checking logic
- Upgrade workflows
- Implementation examples

#### [Delete-Data-Refactoring.md](Delete-Data-Refactoring.md)

Refactoring notes for data deletion functionality.

**For:** Developers (historical)
**Topics:**

- Data cleanup patterns
- Refactoring decisions
- Implementation changes

#### [Lint-Remediation-Workflow.md](Lint-Remediation-Workflow.md)

Workflow for fixing ansible-lint and yamllint issues.

**For:** Developers (process guide)
**Topics:**

- Linting tools setup
- Common issues and fixes
- Automated remediation
- CI integration

### Development Tools & Tips

#### [ansible-tips.md](ansible-tips.md)

Quick Ansible tips and tricks.

**For:** Developers (quick reference)
**Topics:**

- Ansible best practices
- Common patterns
- Troubleshooting tips

#### [Claude-code-review.md](Claude-code-review.md)

Guide for using Claude AI for code review.

**For:** Developers with Claude AI access
**Topics:**

- Code review process
- AI-assisted development
- Quality checks

### Testing & Quality

#### [molecule-strategy.md](molecule-strategy.md)

Molecule testing strategy for solti-containers.

**For:** Developers (testing guide)
**Topics:**

- Test scenarios
- Platform coverage
- CI integration
- Best practices

### Reference Materials

#### [podman-quadlet-article.md](podman-quadlet-article.md)

Comprehensive guide to Podman Quadlets with systemd.

**For:** Developers (learning/reference)
**Topics:**

- Quadlet fundamentals
- Service definitions
- systemd integration
- Examples

#### [role-documentation-template.md](role-documentation-template.md)

Template for writing role documentation.

**For:** Developers (documentation)
**Topics:**

- README structure
- Required sections
- Examples

#### [Env-vars-used.md](Env-vars-used.md)

Inventory of environment variables used across roles.

**For:** Developers (reference)
**Topics:**

- Variable naming
- Usage patterns
- Conflicts

#### [es_resource_limits.md](es_resource_limits.md)

Elasticsearch resource limit configuration.

**For:** Operators (configuration)
**Topics:**

- Memory limits
- CPU allocation
- Performance tuning

### Sprint Reports

Directory: [sprints/](sprints/)

Sprint retrospectives and progress reports.

**For:** Developers and project managers
**Topics:**

- Sprint goals and outcomes
- Velocity tracking
- Lessons learned

### Inventory Examples

Directory: [inventory/](inventory/)

Example inventory configurations.

**For:** Users and developers
**Topics:**

- Inventory structure
- Variable examples
- Configuration patterns

## Organization Guidelines

### Architecture Documents

Should include:

- Problem statement
- Solution approach
- Trade-offs considered
- Implementation guidance
- Examples

### Decision Records

Should document:

- Context and problem
- Options considered
- Decision made
- Consequences
- Date and authors

### Pattern Guides

Should provide:

- Clear examples
- When to use
- Anti-patterns to avoid
- Related patterns

## Related Documentation

- **[solti-containers README](../README.md)** - User-facing documentation
- **[solti-containers CLAUDE.md](../CLAUDE.md)** - Collection-specific context
- **[Root CLAUDE.md](../../CLAUDE.md)** - Multi-collection development context
- **[solti-docs repository](https://github.com/jackaltx/solti-docs)** - Public philosophy docs

## Usage Notes

**Target Audience:** Primarily for developers working on solti-containers and those implementing similar patterns.

**Not User Documentation:** For user guides, see the main [README.md](../README.md) and role-specific READMEs.

---

*Part of the SOLTI (Systems Oriented Laboratory Testing & Integration) project*

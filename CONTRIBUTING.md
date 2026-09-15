# Contributing to RENTASALUD

Thank you for your interest in contributing to RENTASALUD! This document provides guidelines and instructions for contributing.

## Code of Conduct

By participating in this project, you agree to maintain a respectful and inclusive environment. We expect all contributors to:

- Be respectful of differing viewpoints and experiences
- Accept constructive criticism gracefully
- Focus on what is best for the research community
- Show empathy towards other community members

## How to Contribute

### Reporting Issues

If you find a bug or have a suggestion:

1. Check if the issue already exists in the [GitHub Issues](https://github.com/migariane/RENTASALUD/issues)
2. If not, create a new issue with a clear title and description
3. Include steps to reproduce (for bugs) or rationale (for features)
4. Add relevant labels (bug, enhancement, documentation, etc.)

### Submitting Changes

1. **Fork the repository** and create your branch from `main`
2. **Make your changes** following the code style guidelines below
3. **Test your changes** by running the pipeline:
   ```bash
   cd Analysis
   RENTASALUD_CI_MODE=true Rscript 00_run_all.R
   ```
4. **Commit your changes** with clear, descriptive messages
5. **Submit a pull request** with a description of your changes

### Code Style Guidelines

#### R Code

- Use descriptive variable names in Spanish (matching existing code)
- Add comments explaining complex logic (bilingual OK, prefer Spanish for consistency)
- Follow the existing indentation (2 spaces)
- Document functions with their purpose, inputs, and outputs
- Keep lines under 100 characters when practical

#### Documentation

- Update README.md if you change functionality
- Update REPRODUCIBILITY.md if you change output formats
- Use clear, concise language

### Commit Messages

- Use present tense ("Add feature" not "Added feature")
- Use imperative mood ("Fix bug" not "Fixes bug")
- Reference issues when relevant ("Fix #123: correct age calculation")

## Development Setup

### Prerequisites

- R 4.4 or later
- Required packages: `dplyr`, `sf`, `readr`, `tidyr`, `ggplot2`, `scales`

### Running Tests

The CI mode uses synthetic data to verify the pipeline runs correctly:

```bash
cd Analysis
RENTASALUD_CI_MODE=true Rscript 00_run_all.R
```

Outputs go to `Resultados/test_run/` to avoid overwriting production results.

### Verifying Results

After changes, verify outputs match expected values in [`REPRODUCIBILITY.md`](REPRODUCIBILITY.md).

## Areas for Contribution

We particularly welcome contributions in:

- **Documentation:** Improving clarity, fixing typos, adding examples
- **Visualization:** Enhancing the Shiny app or output figures
- **Methods:** Suggesting alternative statistical approaches with justification
- **Accessibility:** Making the atlas more accessible
- **Internationalization:** Translating documentation to other languages

## Data Access

The BDLPA microdata is restricted. If you need access for research purposes:

1. Contact [IECA](https://www.juntadeandalucia.es/institutodeestadisticaycartografia/)
2. Submit a formal data request explaining your research purpose
3. Agree to the data use terms

For testing without real data, use the CI mode which generates synthetic data.

## Questions?

If you have questions about contributing:

- Open a [GitHub Discussion](https://github.com/migariane/RENTASALUD/discussions)
- Contact the maintainer: mluquefe@ugr.es

## License

By contributing, you agree that your contributions will be licensed under the MIT License.

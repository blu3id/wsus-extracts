### WSUS-Extracts

This repository provides a limited subset of what is provided by [OSDSUS](https://github.com/OSDeploy/OSDSUS). Extracts from the WSUS Catalogue are provided in `.json` format only for the following products, builds and architectures:

- Windows 10 (x64)
    - [21H2](windows-10-21h2.json)
    - [22H2](windows-10-22h2.json)

#### Updates

This repository and the extracts should auto-update on "[Patch Tuesday](https://en.wikipedia.org/wiki/Patch_Tuesday)" (2nd Tuesday of the month). Updates are created as [pull requests](/pulls) that will be manually merged. Updates are powered by a scheduled [GitHub Action](https://github.com/features/actions) that can be found in `.github\workflows`.

#### Support and Additional Products / Builds / Architectures

This repository was created after [this](https://github.com/OSDeploy/OSDSUS/issues/6) issue in the [OSDSUS](https://github.com/OSDeploy/OSDSUS) repository to provided an alternate (and automated) source for a specific use case of [OSDSUS](https://github.com/OSDeploy/OSDSUS). Therefore additional Products / Builds / Architectures will not be added on request. No support will be provided.
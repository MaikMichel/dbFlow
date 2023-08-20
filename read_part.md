## dbFlow CheatSheet

### Setup / Configuration

#### Install setup (Only Once)
Prepared Scritps in folder `db/_setup` will be run

```bash
.dbFlow/setup.sh --install
```
> !!! => Will remove users/schemas when running in force mode


### Deployment

#### Build initial deployment
All files will be bundeled and install files will be generated

```bash
.dbFlow/build.sh --init --version 1.0.0
```

The deployment artefact will be placed in the configured depot folder

#### Apply initial deployment
Deplyment artifact will be unpacked in current folder and installation routines will run

```bash
.dbFlow/apply.sh --init --version 1.0.0
```
> !!! Initial deployments will clear all included schemas at beginning

#### Build patch deployment
Any files that have been changed between commits, or between tags, will be bundled together and install files will be generated.

```bash
.dbFlow/build.sh --patch --version 1.0.0 --start commit-a --end commit-b
```

Deployment artifact will be placed in configured depot folder

#### Apply initial deployment
Deployment artefact will be unpacked in current folder and installation routines will run

```bash
.dbFlow/apply.sh --patch --version 1.0.0
```


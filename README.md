<div align='center'>
  <img src="docs/images/logo.png" align="center" width="400px"/>

  > Deployment framework for Oracle Database Applications

  <a href='https://github.com/maikmichel/dbflow/releases'><img src='https://img.shields.io/github/v/release/maikmichel/dbflow?color=%23FDD835&label=version&style=for-the-badge'></a>
  <a href='https://github.com/maikmichel/dbflow/blob/main/LICENSE'><img src='https://img.shields.io/github/license/maikmichel/dbflow?style=for-the-badge'></a>
</div>

---

<div align='center'>

### Quick Links

<a href='https://maikmichel.github.io/dbFlow/'><img src='https://img.shields.io/badge/DOCS-gray?style=for-the-badge'></a> <a href='https://maikmichel.github.io/dbFlow/start/'><img src='https://img.shields.io/badge/GETTING STARTED-blue?style=for-the-badge'></a> <a href='https://github.com/MaikMichel/dbFlow/blob/master/CHANGELOG.md'><img src='https://img.shields.io/badge/CHANGELOG-green?style=for-the-badge'></a>

</div>

---
<br/>

**dbFlow** is a deployment tool / framework for database driven applications in the oracle environment, mainly in the area of Oracle APEX. With **dbFlow** you can create and deploy multi-layered applications. **dbFLow** is powered by Git and can build a deployment / patch from different commit states, which can then be rolled out to different target instances.

## Features

- Create an Oracle Database / APEX Project per command line
- Install dependent features like Logger, utPLSQL, teplsql, ...
- Use a fully customizable deployment flow based on Git Flow
- Configure your project dependencies
- Generate and process changelogs
- Create and test nightlybuilds
- Build artifacts / patches based on Git diffs
- Deploy patches to target instances
- Copy configuration to other instances
- Generate Test deployments as Insert Scripts


### Generate project "demo"

  ![ScreenCast:  Generate demo project](docs/images/generate_demo.gif)

### Install project "demo"

  ![ScreenCast:  Install demo project](docs/images/install_demo.gif)

</br>
</br>

<a href='https://marketplace.visualstudio.com/items?itemName=MaikMichel.dbflow'><img src='docs/images/dbflux.png' width="100px" align="right"></a>
## Works best with dbFLux [dbFlux](https://marketplace.visualstudio.com/items?itemName=MaikMichel.dbflow)


<br/>

>### With that in place you get the ability to
>- compile SQL or PLSQL based on folder structure
>- compile all used schemas
>- execute tests based on folder structure
>- minify and upload JavaScript to your APEX Application
>- minify and upload CSS to your Application
>- Export APEX Applications
>- Export REST Modules
>- Export DB Schema or Objects
>- Export Static Application Files
>- Create and Upload binary files for reporting (AOP)
>- Many small development improvements

</br>
</br>

## Getting Started

### With a One-Liner

```bash

# Without parameter current directory is used
curl -sS https://raw.githubusercontent.com/MaikMichel/dbFlow/master/install.sh | bash

# Add targetfolder as parameter
curl -sS https://raw.githubusercontent.com/MaikMichel/dbFlow/master/install.sh | bash -s <targetfolder>

```

### Manual

1. create a git repositoy
2. add dbFlow as `.dbFlow` submodule to your project

### Generate project and setup install to database

3. run `.dbFlow/setup.sh --generate <project_name>`
4. answer some question based on your requirements
6. Review files, generated for you and make some adjustments
5. after that just run `.dbFlow/setup.sh --install`


```bash
# create a folder for your project and change directory into
$ mkdir demo && cd demo

# init your project with git
$ git init

# clone dbFlow as submodule
$ git submodule add https://github.com/MaikMichel/dbFlow.git .dbFlow

# generate and switch to your development branch
$ git checkout -b develop

# generate project structure
$ .dbFlow/setup.sh --generate <project_name>

# after processing the wizard steps, just install
$ .dbFlow/setup.sh --install
```


## Documentation
  [Just read the docs](https://maikmichel.github.io/dbFlow/)

## Frequently Asked Question

> Git creates wrong filenames and dbFlow can't copy / rsync them in a right manner

- This is a git problem and you can turn it off by using following option:
```bash
$ git config --global core.quotepath off
```

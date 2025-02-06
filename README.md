# Vault Script - StackVault.sh

## Installation
To install the script, use one of the following commands:
```sh
./stackvault.sh --install
```

To make the script's aliases persistent in memory, execute:
```sh
source ./stackvault.sh
```
Or:
```sh
. ./stackvault.sh
```

## Uninstallation
To uninstall the script along with the alias:
```sh
./stackvault.sh --uninstall
```

To uninstall the script with the alias:
```sh
stackvault --uninstall
```

## Setup
To change the script’s setup without uninstalling it and move the current installation to a new location:
```sh
./stackvault.sh --setup newlocationdir/
```

To set up the script with the alias:
```sh
stackvault --setup newlocationdir/
```

## Usage

### Pushing an Item to the Vault
To push an item (directory or file) into the vault:
```sh
./stackvault.sh push existingdir
```

To push an item using the alias:
```sh
apush item
```

To push an item into the vault with a password:
```sh
./stackvault.sh push -p existingdir/
```

To push an item with the alias and a password:
```sh
appush item
```

### Popping an Item from the Vault
To retrieve an item from the vault:
```sh
./stackvault.sh pop
```

To retrieve an item using the alias:
```sh
apop
```

To retrieve an item with password protection:
```sh
./stackvault.sh pop -p
```

To retrieve an item with the alias and password protection:
```sh
appop
```
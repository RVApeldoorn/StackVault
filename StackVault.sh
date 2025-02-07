!/usr/bin/env bash

DEFAULT_VAULT_DIR="$HOME/vault"
CONFIG_FILE="$HOME/vault.conf"
ARCHIVE_FILE="archive.vault"
STACK_FILE="stack.vault"
NOTHING_FILE="nothing.txt"

#Trap for unexpected termination
trap "cleanup" SIGINT SIGTERM

function cleanup() {
    echo "Process interrupted. Cleaning up..."
    #Rollback to restore the original state
    recover_backup
    return 1
}

function load_config() {
    #Load archive path and encryption status from the config file
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE" || { handle_error "Could not read configuration file"; return 1; }

        #Check the encryption status
        if [[ "$ENCRYPTED" != "0" && "$ENCRYPTED" != "1" ]]; then
            handle_error "Invalid encryption state in config file: $ENCRYPTED. It must be 0 or 1."
            return 1
        fi
        #Check if VAULT_DIR is set. if not, set to default
        if [ -z "$VAULT_DIR" ]; then
            VAULT_DIR="$DEFAULT_VAULT_DIR"
            echo "VAULT_DIR not defined in configuration file. Using default vault directory: $VAULT_DIR"
        fi
    else
        VAULT_DIR="$DEFAULT_VAULT_DIR"  #Use the default if the config file is missing
        echo "Configuration file not found. Using default vault directory: $VAULT_DIR"
    fi
}

function install_dependencies() {
    echo "Checking for required dependencies..."

    #Check gnupg
    if ! command -v gpg &> /dev/null; then
        echo "GnuPG not found. Installing GnuPG..."
        sudo apt install -y gnupg
        echo "GnuPG installation complete."
    else
        echo "GnuPG is already installed."
    fi

    #Check gzip 
    if ! command -v gzip &> /dev/null; then
        echo "gzip not found. Installing gzip..."
        sudo apt install -y gzip
        echo "gzip installation complete."
    else
        echo "gzip is already installed."
    fi
}

function install() {
    echo "function install"

    install_dependencies
    
    #Check if a valid directory name is passed; else, use default
    if [ -n "$1" ]; then
        VAULT_DIR=$(realpath "$1")
    else
        VAULT_DIR=$(realpath "$DEFAULT_VAULT_DIR")
    fi
    
    #Create vault directory if it doesn't exist
    if [ ! -d "$VAULT_DIR" ]; then
        mkdir -p "$VAULT_DIR" || { handle_error "Failed to create vault directory at $VAULT_DIR"; return 1; }
    else
        handle_error "Vault directory already exists!"
        return 1
    fi

    # Set vault directory permissions
    chmod 700 "$VAULT_DIR" || { handle_error "Failed to set permissions for vault directory"; return 1; }

    #Create the 'nothing.txt' file temporarily
    echo "almost nothing" > "$VAULT_DIR/$NOTHING_FILE" || { handle_error "Failed to create nothing.txt file"; return 1; }

    #Compress the archive and add 'nothing.txt' to it
    ARCHIVE_FILE="${ARCHIVE_FILE}.gz"
    tar czf "$VAULT_DIR/$ARCHIVE_FILE" -C "$VAULT_DIR" "$NOTHING_FILE" || { handle_error "Failed to create initial archive"; return 1; }

    # Set archive file permissions
    chmod 600 "$VAULT_DIR/$ARCHIVE_FILE" || { handle_error "Failed to set permissions for archive file"; return 1; }

    #Remove the 'nothing.txt' file from the vault directory after archiving it
    rm "$VAULT_DIR/$NOTHING_FILE" || { handle_error "Failed to delete temporary nothing.txt file"; return 1; }

    #Generate vault configuration file
    echo "VAULT_DIR=$VAULT_DIR" > "$CONFIG_FILE" || { handle_error "Failed to create config file"; return 1; }
    echo "ENCRYPTED=0" >> "$CONFIG_FILE" || { handle_error "Failed to initialize encryption state in config file"; return 1; }

    #Set config file to read-only
    chmod 600 "$CONFIG_FILE" || { handle_error "Failed to set config file permissions"; return 1; }
    
    touch "$VAULT_DIR/$STACK_FILE" || { handle_error "Failed to create stack file"; return 1; }

    # Set stack file permissions
    chmod 600 "$VAULT_DIR/$STACK_FILE" || { handle_error "Failed to set permissions for stack file"; return 1; }

    #Create aliases for this session
    SCRIPT_NAME=$(basename "${BASH_SOURCE[0]}")
    alias stackvault="./$SCRIPT_NAME"
    alias vpush="./$SCRIPT_NAME push"
    alias vppush="./$SCRIPT_NAME push -p"
    alias vpop="./$SCRIPT_NAME pop"
    alias vppop="./$SCRIPT_NAME pop -p"

    echo "Installation complete. Vault directory: $VAULT_DIR"
    return 0
}

function setup() {
    echo "function setup"

    #Check if a new directory location is provided
    NEW_VAULT_DIR=$(realpath "$1")
    if [ -z "$NEW_VAULT_DIR" ]; then
        handle_error "No new directory specified for setup"
        return 1
    fi

    #Ensure the new directory does not already exist to prevent overwriting
    if [ -d "$NEW_VAULT_DIR" ]; then
        handle_error "The specified directory already exists"
        return 1
    fi

    #Source the existing configuration file to get the current VAULT_DIR
    source "$CONFIG_FILE" || { handle_error "Could not read configuration file"; return 1; }

    #Move the current vault directory to the new directory
    mv "$VAULT_DIR" "$NEW_VAULT_DIR" || { handle_error "Failed to move vault to $NEW_VAULT_DIR"; return 1; }

    #Update VAULT_DIR path in the configuration file
    sed -i "s|^VAULT_DIR=.*|VAULT_DIR=$NEW_VAULT_DIR|" "$CONFIG_FILE" || { 
        mv "$NEW_VAULT_DIR" "$VAULT_DIR"
        handle_error "Failed to update configuration file with new vault path"; 
        return 1; 
    }

    echo "Setup complete. Vault has been relocated to: $NEW_VAULT_DIR"
    return 0
}

function handle_error() {
    echo "function handle_error"
    echo "Error: $1"

    recover_backup  
    
    return 1 
}

function create_backup() {
    local compressed_raw="$VAULT_DIR/$ARCHIVE_FILE.gz"
    local compressed_encrypted="$VAULT_DIR/$ARCHIVE_FILE.gz.gpg"

    #Only back up the compressed archive if it exists
    if [ -f "$compressed_raw" ]; then
        cp "$compressed_raw" "$compressed_raw.bak" || { handle_error "Failed to create backup of raw compressed archive"; return 1; }
    elif [ -f "$compressed_encrypted" ]; then
        cp "$compressed_encrypted" "$compressed_encrypted.bak" || { handle_error "Failed to create backup of encrypted compressed archive"; return 1; }
    fi

    #Back up the stack file if it exists
    if [ -f "$VAULT_DIR/$STACK_FILE" ]; then
        cp "$VAULT_DIR/$STACK_FILE" "$VAULT_DIR/$STACK_FILE.bak" || { handle_error "Failed to create backup of stack file before operation"; return 1; }
    fi
}

function recover_backup() {
    #Check which backup file exists to rollback
    if [ -f "$VAULT_DIR/$ARCHIVE_FILE.gz.gpg.bak" ]; then
        rm -f "$VAULT_DIR/$ARCHIVE_FILE" "$VAULT_DIR/$ARCHIVE_FILE.gpg" "$VAULT_DIR/$ARCHIVE_FILE.gz" "$VAULT_DIR/$ARCHIVE_FILE.gz.gpg"
        
        mv "$VAULT_DIR/$ARCHIVE_FILE.gz.gpg.bak" "$VAULT_DIR/$ARCHIVE_FILE.gz.gpg" || { 
            echo "Rollback failed: Unable to restore archive from backup."
            return 1
        }
        rm -f "$VAULT_DIR/$ARCHIVE_FILE.gpg.gz.bak"

    elif [ -f "$VAULT_DIR/$ARCHIVE_FILE.gz.bak" ]; then
        rm -f "$VAULT_DIR/$ARCHIVE_FILE" "$VAULT_DIR/$ARCHIVE_FILE.gpg" "$VAULT_DIR/$ARCHIVE_FILE.gz" "$VAULT_DIR/$ARCHIVE_FILE.gz.gpg"
        
        mv "$VAULT_DIR/$ARCHIVE_FILE.gz.bak" "$VAULT_DIR/$ARCHIVE_FILE.gz" || { 
            echo "Rollback failed: Unable to restore unencrypted archive from backup."
            return 1
        }
        rm -f "$VAULT_DIR/$ARCHIVE_FILE.gz.bak"
    else
        echo "No backup archive found to roll back."
    fi

    #Restore the stack file if it exists
    if [ -f "$VAULT_DIR/$STACK_FILE.bak" ]; then
        rm -f "$VAULT_DIR/$STACK_FILE"
        mv "$VAULT_DIR/$STACK_FILE.bak" "$VAULT_DIR/$STACK_FILE" || echo "Rollback failed: Unable to restore stack file from backup."
        rm -f "$VAULT_DIR/$STACK_FILE.bak"
    else
        echo "No stack file backup found to roll back."
    fi
}

function pop() {
    echo "function pop"

    USE_PASSWORD=0

    #Check for the -p flag for when archive is encrypted
    if [[ "$1" == "-p" ]]; then
        USE_PASSWORD=1
    fi

    create_backup || return 1

    #Check if the vault is encrypted
    if [ "${ENCRYPTED:-0}" -eq 1 ]; then
        if [ "$USE_PASSWORD" -ne 1 ]; then
            handle_error "A password flag is required to pop from an encrypted vault."
            return 1
        fi
        
        #Decrypt the archive
        decrypt || return 1
    fi

    #Check if the stack file exists and is not empty
    if [ ! -s "$VAULT_DIR/$STACK_FILE" ]; then
        handle_error "Vault is empty"
        return 1
    fi

    #Get the last pushed item from the stack
    ITEM=$(tail -n 1 "$VAULT_DIR/$STACK_FILE")

    decompress || return 1

    #Extract the item from the archive into the current directory
    tar xvf "$VAULT_DIR/$ARCHIVE_FILE" "$ITEM" -C "$(pwd)" || { handle_error "Failed to extract $ITEM"; return 1; }

    #Remove the item from the archive
    tar --delete -f "$VAULT_DIR/$ARCHIVE_FILE" "$ITEM" || { handle_error "Failed to remove $ITEM from archive"; return 1; }

    #Update the stack and remove the last item
    sed -i '$d' "$VAULT_DIR/$STACK_FILE" || { handle_error "Failed to update stack"; return 1; }

    #Recompress
    compress || return 1
    
    #If the vault was encrypted, re-encrypt it
    if [ "$ENCRYPTED" -eq 1 ]; then
        encrypt "$PASSWORD" || { handle_error "Failed to encrypt archive after popping item."; return 1; }
    fi

    rm -f "$VAULT_DIR/$ARCHIVE_FILE.gz.bak" "$VAULT_DIR/$ARCHIVE_FILE.gz.gpg.bak" "$VAULT_DIR/$STACK_FILE.bak" # Remove backup on succes
    echo "Successfully popped $ITEM from the vault."
    return 0
}

function push() {
    echo "function push"

    USE_PASSWORD=0

    #Assign item based on if "-p" is passed
    if [[ "$1" == "-p" ]]; then
        USE_PASSWORD=1
        ITEM="$2"
    else
        ITEM="$1"
    fi

    if [ ! -e "$ITEM" ]; then
        handle_error "Item '$ITEM' does not exist"
        return 1
    fi

    create_backup || return 1

    #Check if the vault is encrypted
    if [ "${ENCRYPTED:-0}" -eq 1 ]; then
        if [ "$USE_PASSWORD" -ne 1 ]; then
            handle_error "A password flag is required to push to an encrypted vault."
            return 1
        fi

        #Decrypt the archive
        decrypt || return 1
    fi

    decompress || return 1
    
    #Check if item already exists in the archive
    if tar tf "$VAULT_DIR/$ARCHIVE_FILE" | grep -q "^$(basename "$ITEM")$"; then
        handle_error "Item '$ITEM' already exists at this level in the vault."
	return 1
    fi

    tar rvf "$VAULT_DIR/$ARCHIVE_FILE" "$ITEM" || { handle_error "Failed to add $ITEM to the archive"; return 1; }
    echo "$ITEM" >> "$VAULT_DIR/$STACK_FILE" || { handle_error "Failed to update stack file"; return 1; }

    compress || return 1

    #If a password flag was provided and archive was not encrypted, encrypt the archive
    if [[ "$USE_PASSWORD" -eq 1 ]]; then
        encrypt || return 1
        if [ "$ENCRYPTED" -ne 1 ]; then
            sed -i "s/^ENCRYPTED=.*/ENCRYPTED=1/" "$CONFIG_FILE" || { handle_error "Failed to update encryption status in config file"; return 1; }
        fi
    fi

    rm -f "$VAULT_DIR/$ARCHIVE_FILE.gz.bak" "$VAULT_DIR/$ARCHIVE_FILE.gz.gpg.bak" "$VAULT_DIR/$STACK_FILE.bak" # Remove backup on success
    echo "Successfully pushed $ITEM into the vault."
    return 0
}

function uninstall() {
    echo "function uninstall"

    if [ ! -f "$CONFIG_FILE" ]; then
        handle_error "Configuration file not found. Uninstallation may have been completed already."
        return 1
    fi

    source "$CONFIG_FILE" || { handle_error "Could not read configuration file"; return 1; }

    unalias stackvault 2>/dev/null
    unalias vpush 2>/dev/null
    unalias vppush 2>/dev/null
    unalias vpop 2>/dev/null
    unalias vppop 2>/dev/null

    rm -rf "$VAULT_DIR" || { handle_error "Failed to remove vault directory"; return 1; }

    rm "$CONFIG_FILE" || { handle_error "Failed to remove config file"; return 1; }

    echo "Uninstallation complete. Vault has been removed."
    return 0
}

function decrypt() {
    if [ ! -f "$VAULT_DIR/$ARCHIVE_FILE.gz.gpg" ]; then
        handle_error "No encrypted archive file found to decrypt."
        return 1
    fi

    #Prompt for the password
    echo "Enter the passphrase to decrypt the archive:"
    read -s PASSPHRASE

    #Decrypt the archive using the given password
    echo "$PASSPHRASE" | gpg --batch --yes --passphrase-fd 0 -d -o "$VAULT_DIR/$ARCHIVE_FILE.gz" "$VAULT_DIR/$ARCHIVE_FILE.gz.gpg" \
        || { handle_error "Failed to decrypt archive"; return 1; }

    #Export the password for later use in encryption
    export ENCRYPT_PASSPHRASE="$PASSPHRASE"
}

function encrypt() {
    if [ ! -f "$VAULT_DIR/$ARCHIVE_FILE.gz" ]; then
        handle_error "No archive file found to encrypt."
        return 1
    fi

    #Check if we have an existing password from decryption
    if [ -z "$ENCRYPT_PASSPHRASE" ]; then
        #If no password exists, this is the first-time encryption
        echo "Enter a new passphrase to encrypt the archive:"
        read -s ENCRYPT_PASSPHRASE
        echo "Confirm the passphrase:"
        read -s CONFIRM_PASSPHRASE

        #Check if the passwords match
        if [ "$ENCRYPT_PASSPHRASE" != "$CONFIRM_PASSPHRASE" ]; then
            handle_error "Passphrases do not match. Encryption aborted."
            return 1
        fi
    fi

    #Encrypt the archive using the provided or stored password
    echo "$ENCRYPT_PASSPHRASE" | gpg --batch --yes --symmetric --cipher-algo AES256 --passphrase-fd 0 \
        -o "$VAULT_DIR/$ARCHIVE_FILE.gz.gpg" "$VAULT_DIR/$ARCHIVE_FILE.gz" \
        || { handle_error "Failed to encrypt archive"; return 1; }

    #Clean up the unencrypted archive
    rm -f "$VAULT_DIR/$ARCHIVE_FILE.gz" || { handle_error "Failed to remove the unencrypted archive after encryption"; return 1; }

    #Unset the passphrase after encryption
    unset ENCRYPT_PASSPHRASE
}

function compress() {
    if [ -f "$VAULT_DIR/$ARCHIVE_FILE" ]; then
        gzip "$VAULT_DIR/$ARCHIVE_FILE" || { handle_error "Failed to compress raw archive"; return 1; }
    else
        handle_error "No archive found to compress."
        return 1
    fi
}

function decompress() {
    if [ -f "$VAULT_DIR/$ARCHIVE_FILE.gz" ]; then
        gunzip "$VAULT_DIR/$ARCHIVE_FILE.gz" || { handle_error "Failed to decompress raw archive"; return 1; }
    else
        handle_error "No compressed archive found to decompress."
        return 1
    fi
}

function main() {
    echo "function main"

    #Check for sufficient arguments
    if [ "$#" -lt 1 ]; then
        echo "Usage: $0 {install|setup|push|pop|uninstall}"
        return 1
    fi

    #Read command and handle accordingly
    COMMAND="$1"
    shift  #Remove command from arguments

    case "$COMMAND" in
        --install)
            install "$@"
            ;;
        --setup)
            setup "$@"
            ;;
        push)
            push "$@"
            ;;
        pop)
            pop "$@"
            ;;
        --uninstall)
            uninstall
            ;;
        *)
            echo "Unknown command: $COMMAND"
            return 1
            ;;
    esac
}

load_config
main "$@"
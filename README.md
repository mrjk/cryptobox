# cryptobox

Zero knowledge per identity vaults.


Tool to manage secrets in a git repo. The goal here is to provide an easy way to track secret file in a public git repo. It also provides basic secret primitives such as SSH or GPG. Can be easily extended with plugins.

Require AGE encryption tool.


## Quickstart

Create new identities:
```
cryptobox id new alice
cryptobox id new bob
cryptobox id new cory
```

Create a vault for alice and open it:
```
cryptobox vault new vault_alice alice
```

Let's update a secret:
```
echo "Alice secrets!" >> vaults/vault_alice/README.md
cat vaults/vault_alice/README.md
```

Open and close personal vault ID:
```
cryptobox vault close vault_alice
```

Create new and delete vault:
```
cryptobox vault close # Seal ALL local vault
cryptobox vault rm NAME # Delete vault
```

List and manipulate vaults:
```
cryptobox vault ls  # List vaults and associated IDs

# WIP
cryptobox vault recipients ls NAME
cryptobox vault recipients set NAME [ID,...]
cryptobox vault recipients rm NAME [ID,...]
cryptobox vault recipients add NAME [ID,...]
```

Automatic password unlock with local keyring (via `secret-tool`):
```
cryptobox keyring set ID     # Add new password
cryptobox keyring rm ID      # Remove password
cryptobox keyring ls         # List current saved keys
cryptobox keyring clear      # Clear keyring from all passwords

```

Enable default id in shell:
```
eval "$(cryptobox --shell enable ID)"
```


## How it works ?

Cryptforge brings few concepts.

### Identities 

Represent an identity or an entity. It can be your name, a pseudo, or anything. To each identity is assigned a personal vault, to store secrets in it. You can create as many identities you want, split secrets among different identities or just use one identity if that fit to you.

Am identity is actually a password protected `age` public/private key pair. They live in `idents/id_<NAME>.age`. To open this file, even to read the public key, you must provide the password.

### Vaults

A vault is an `age` encrypted directory. Each identities own it's private vault, named `id_<NAME>` and lives in `vaults/id_<NAME>.age` file. Vaults related with idents are always prefixed with `id_`.

It also possible to create new vaults, and set which other identities can read in it or not. 

A vault can be opened or closed. When opened, the actual content of the age file is decrypted and copied into `store/<VAULT_NAME>`. You can make modification, read and write like regular files. When
closed, the content of the whole directory is tared and encrypted, and local files removed.

### Keyring

This is an helper tool to store in local keyring your main identities secrets.

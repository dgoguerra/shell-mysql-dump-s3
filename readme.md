
## mysql-dump-s3.sh

### Installation

Installing the script:

```
sudo make install
```

will copy it to `/usr/local/bin/mysql-dump-s3.sh`, where
it should be available through most user's path.

### Example usage

To avoid giving credentials to the script, you can setup your
`~/.my.cnf` file:

```
[mysql]
user = db_user
password = db_password

[mysqldump]
user = db_user
password = db_password
```

Having done that, a basic use of the script is:

```sh
mysql-dump-s3.sh --database db_name --s3-bucket bucket_name --s3-folder /backups/
```

Alternatively, credentials can be passed to the script. Basically, the argument
passed to the `--dump-extra-args` option will be passed to `mysqldump` as extra
arguments:

```sh
mysql-dump-s3.sh \
    --database db_name \
    --s3-bucket bucket_name \
    --s3-folder /backups/ \
    --dump-extra-args "-udb_user -pdb_password" \
```

A more extended example:

```sh
mysql-dump-s3.sh \
    --database db_name \
    --s3-bucket bucket_name \
    --s3-folder /backups/ \
    # passing some arguments to mysqldump
    --dump-extra-args \
        "-udb_user -pdb_password --ignore-table=db_name.table_to_ignore" \
    # use a custom dumps folder,  instead of /tmp/mysql-dump-s3
    --dump-folder /app-data/dumps \
    # don't remove the local dumps after uploading to S3
    --preserve-raw-dump \
    # remove files in the dumps folder older than 10 days
    --rm-dumps-older-than 10
```

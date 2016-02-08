#!/bin/bash
 
# File name
readonly PROGNAME=$(basename $0)
# File name, without the extension
readonly PROGBASENAME=${PROGNAME%.*}
# Arguments
readonly ARGS="$@"
# Arguments number
readonly ARGNUM="$#"

awsCmd="/usr/local/bin/aws"
rmCmd="/bin/rm"

usage() {
    echo
    echo "Dump a MySQL database, compress it and upload it to AWS S3."
    echo
    echo "Usage: $PROGNAME --database <database> --s3-bucket <bucket> --s3-folder <folder> [options]..."
    echo
    echo "General Options:"
    echo
    echo "  -h, --help"
    echo "      This help text."
    echo
    echo "  -d <database>, --database <database>"
    echo "      Database name."
    echo
    echo "  --output-prefix <prefix>"
    echo "      Output file prefix."
    echo
    echo "  --s3-bucket <bucket name>"
    echo "      Destination bucket name."
    echo
    echo "  --s3-folder <bucket folder>"
    echo "      Destination bucket folder."
    echo
    echo
    echo "Extra Options:"
    echo
    echo "  --dry-run"
    echo "      Option for debugging and testing the script with the given"
    echo "      options before running it. Pretend to execute the actions,"
    echo "      outputting the commands instead."
    echo
    echo "  --dump-extra-args <extra args>"
    echo "      Dump command extra arguments."
    echo
    echo "  --dump-folder <folder>"
    echo "      Folder to use to download the dump."
    echo
    echo "  --preserve-raw-dump"
    echo "      Don't delete the raw database dump file after execution."
    echo
    echo "  --preserve-zip-dump"
    echo "      Don't delete the compressed database dump file after execution."
    echo
    echo "  --preserve-all"
    echo "      Don't delete any temporary files after execution. This option"
    echo "      equals to using --preserve-raw-dump and --preserve-zip-dump."
    echo
    echo "  --rm-dumps-older-than"
    echo "      To be used when --preserve-raw-dump or --preserve-zip-dump are"
    echo "      set, it removes files in the dump folder older than the given"
    echo "      amount of days before starting the dump."
    echo
    echo "  --"
    echo "      Do not interpret any more arguments as options."
    echo
}


errorExit() {
    local message="$1"
    echo "error: $message. Rerun with '--help' to see the available options." 1>&2
    exit 1
}

checkCmdExists() {
    local cmd="$1"
    command -v "$cmd" >/dev/null 2>&1 || errorExit "'$cmd' appears not to be installed. Aborting"
}

makeFolderIfNotExists() {
    local folder="$1"

    if [ ! -d "$folder" ]; then
        if [ "$dryRun" == "1" ]; then
            echo "mkdir -p \"$folder\""
        else
            mkdir -p "$folder"
        fi
    fi
}

dumpDb() {
    local dbName="$1"
    local output="$2"

    if [ "$dryRun" == "1" ]; then
        echo "mysqldump configtool $dumpExtraArgs --single-transaction > \"$output\""
    else
        mysqldump configtool $dumpExtraArgs --single-transaction > "$output"
    fi
}

# create a compressed file from the given source. Doesn't remove source file
compressFile() {
    local source="$1"
    local dest="$2"

    if [ "$dryRun" == "1" ]; then
        echo "tar -cvzf \"$dest\" \"$source\""
    else
        tar -cvzf "$dest" "$source"
    fi
}

# obtain the S3 bucket's region from its name
getBucketRegion() {
    local bucketName="$1"
    "$awsCmd" s3api get-bucket-location --bucket $bucketName --output text
}

fullBucketPath() {
    local bucketName="$1"
    local bucketFolder="$2"

    # prepend slash to the bucket folder if it wasn't there
    if [[ ! "$bucketFolder" == "/"* ]]; then
        bucketFolder="/$bucketFolder"
    fi

    echo "s3://${bucketName}${bucketFolder}"
}

# copy the compressed file to S3
copyToS3() {
    local source="$1"
    local bucketName="$2"
    local bucketRegion="$3"
    local destFolder="$4"

    bucketPath=$(fullBucketPath $bucketName $destFolder)

    if [ "$dryRun" == "1" ]; then
        echo "$awsCmd s3 cp --region \"$bucketRegion\" \"$source\" \"$bucketPath\""
    else
        "$awsCmd" s3 cp --region "$bucketRegion" "$source" "$bucketPath"
    fi
}

removeFilesOlderThan() {
    local folder="$1"
    local olderThanDays="$2"

    if [ "$dryRun" == "1" ]; then
        # check if the folder exists first, it may not exist if we are running
        # with --dry-run
        echo "find \"$folder\" -mtime \"+$olderThanDays\" -exec $rmCmd {} \;"
        [ -d "$folder" ] && find "$folder" -mtime "+$olderThanDays" -exec echo $rmCmd {} \;
    else
        # find "$folder" -name '*.sql' -mtime "+$olderThanDays" -exec $rmCmd {} \;
        find "$folder" -mtime "+$olderThanDays" -exec $rmCmd {} \;
    fi
}


# before doing anything, check that some dependencies we are going to use exist
checkCmdExists "$awsCmd"
checkCmdExists mysqldump


while [ "$#" -gt 0 ]
do
    case "$1" in
    -h|--help)
        usage
        exit 0
        ;;
    -d|--database)
        dbName="$2"
        ;;
    --dump-extra-args)
        dumpExtraArgs="$2"
        # skip the next element in the loop (the current option's argument),
        # in case it also starts by '--'
        shift
        ;;
    --output-prefix)
        outputPrefix="$2"
        ;;
    --s3-bucket)
        bucketName="$2"
        ;;
    --s3-folder)
        bucketFolder="$2"
        ;;
    --dry-run)
        dryRun="1"
        ;;
    --dump-folder)
        dumpFolder="$2"
        ;;
    --preserve-raw-dump)
        preserveRaw="1"
        ;;
    --preserve-zip-dump)
        preserveZip="1"
        ;;
    --preserve-all)
        preserveRaw="1"
        preserveZip="1"
        ;;
    --rm-dumps-older-than)
        rmOldFiles="1"
        rmOlderThanDays="$2"
        ;;
    --)
        break
        ;;
    -*)
        echo "Invalid option '$1'. Rerun with '--help' to see the available options." >&2
        exit 1
        ;;
    # an option argument, continue
    *)  ;;
    esac
    shift
done


if [ "$dbName" == "" ]; then
    errorExit "database must be set"
fi

if [ "$bucketName" == "" ]; then
    errorExit "S3 bucket name must be set"
fi

if [ "$bucketFolder" == "" ]; then
    errorExit "S3 bucket output folder must be set"
fi


if [ "$rmOldFiles" == 1 ] && [ "$rmOlderThanDays" == "" ]; then
    errorExit "--rm-dumps-older-than requires the number of days as an argument"
fi


# if there was no prefix, use the database name
if [ "$outputPrefix" == "" ]; then
    outputPrefix="$dbName"
fi

# if no dumps directory was given, default to /tmp/mysql-dump-s3
if [ "$dumpFolder" == "" ]; then
    dumpFolder="/tmp/mysql-dump-s3"
fi

# create the dumps directory if it doesn't exist...
makeFolderIfNotExists "$dumpFolder"

# only actually move to the dumps folder if the script is not
# being executed with --dry-run, to avoid cd failing if the
# directory doesn't exist
if [ "$dryRun" == "1" ]; then
    echo "cd \"$dumpFolder\""
else
    cd "$dumpFolder"
fi

# if the --rm-dumps-older-than option is set, cleanup the dumps folder
# before starting with the current dump.
if [ "$rmOldFiles" == "1" ]; then
    removeFilesOlderThan "$dumpFolder" "$rmOlderThanDays"
fi

datetime=$(date +%Y%m%d_%H%M%S)
dumpFilename="${outputPrefix}_${datetime}.sql"
dumpZipFilename="$dumpFilename.tar.gz"

bucketRegion=$(getBucketRegion "$bucketName") || errorExit "'$bucketName' bucket's region could not be retrieved. Aborting"

dumpDb "$dbName" "$dumpFilename"

compressFile "$dumpFilename" "$dumpZipFilename"

copyToS3 "$dumpZipFilename" "$bucketName" "$bucketRegion" "$bucketFolder"

# unless the --preserve-raw-dump flag is set, delete the dumped file
if [ ! "$preserveRaw" == "1" ] && [ ! "$dryRun" == "1" ]; then
    "$rmCmd" "$dumpFilename"
fi

# unless the --preserve-zip-dump flag is set, delete the compressed
# dump file
if [ ! "$preserveZip" == "1" ] && [ ! "$dryRun" == "1" ]; then
    "$rmCmd" "$dumpZipFilename"
fi

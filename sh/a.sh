rsync_argu=(-ahP --delete --inplace --no-whole-file)
rsync -n ${rsync_argu[@]} "$@"
echo -ne "are you sure? "
read sure
if [ "$sure" = '' -o "$sure" = 'y' ]; then
  rsync ${rsync_argu[@]} "$@"
fi

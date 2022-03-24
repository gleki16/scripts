rsync -ahnv --delete "$@"
read -p 'are you sure? ' sure
if [ "$sure" = '' -o "$sure" = 'y' ]; then
  rsync -ah --info=progress2 --delete --inplace --no-whole-file "$@"
fi
#!/usr/bin/env bash
rsync -ah --info=progress2 --delete --inplace --no-whole-file $@
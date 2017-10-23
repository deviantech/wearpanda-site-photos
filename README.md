README.md

The master list for our product images.

## To add new images - general

#### Put the image in the correct folder

*SKU-specific images* go in photos/[product category]/[product name]/[SKU]/[photo-here-name-doesn't-matter].jpg

*General product images*, as well as potential *editorial* and *header* images, go in photos/[product category]/[product name]/product/[photo-here-name-doesn't-matter].jpg.

#### Run the renamer script

Photos will be automatically renamed with a meaningful name (based on SKU or product name) and given a number to differentiate between them. Note that any prefixed '!' character survives the rename, and bang (publishable)/non-bang(non-publishable) photos are numbered separately.

## Selecting which images to publish

*SKU-specific images* and *general product photos*: any filename prefixed with a bang ('!') will be copied to the *_live* folder (with the appropriate filename) when the publish script is run.

*Editorial and header images* will only be copied from the *_editorials* and *_headers* subfolders (since these will require manual action to create).

## Uploading Manually

You can drag photos from the *_live* folder after running the prepare, or better yet just run the publish script (bin/publish) to sync automatically. Note: when uploading manually, wait for each folder to complete uploading before dragging another (otherwise Shopify gets confused).

## Uploading Automatically

The publish script (bin/publish) is run as the git pre-commit hook... if you want to check in files that aren't yet valid (ideally only while setting up the initial mirroring), commit with `git commit --no-verify`.


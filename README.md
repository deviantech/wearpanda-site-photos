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

*Editorial and header images* will only be copied from the *_editorials* and *_headers* subfolders (since these will require manual action to create). In these folders the ! is unnecessary, but any file prefixed with ! will expect a square editorial image rather than the usual dimensions (based on the golden ratio).

## Uploading Manually

You can drag photos from the *_live* folder after running the prepare, or better yet just run the publish script (bin/publish) to sync automatically. Note: when uploading manually, wait for each folder to complete uploading before dragging another (otherwise Shopify gets confused).

## Uploading Automatically

The publish script (bin/publish) is run as the git pre-commit hook... if you want to check in files that aren't yet valid (ideally only while setting up the initial mirroring), commit with `git commit --no-verify`.

## One-off Manipulation

There's an `App.call_with_block` method that allows you to run arbitrary ruby code for each ProductDirectory. Use in a script like, for example:

```ruby
    #!/usr/bin/env ruby
    require_relative '../lib/app'

    dir = App.photos_dir

    # Example: copying editorial photo to product dir if accidentally was moved over rather than copied
    App.call_with_block(dir) do
      next unless path =~ /xmas/
      next unless entries('_editorials').length == 1
      editorial = Traversal::File.new(path+'/_editorials/'+entries('_editorials')[0], 1)
      editorial_md5 = editorial.file_hash


      if matched = select_live_photos.select {|k,d| !k.match(/editorial/) }.detect {|key, data| data['source_md5'] == editorial_md5 }
        puts "\t[#{product_dir_name.cyan}] editorial has hash #{editorial_md5}, which matches photo #{matched[0]}".light_black
      else
        puts "\t[#{product_dir_name.cyan}] Would copy #{editorial.live_name} to products dir"
        FileUtils.cp editorial.full_path, path+'/product/temp_from_editorial.jpg'
      end
    end
```
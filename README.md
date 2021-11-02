# BOSH Release for nfsclient

This is a workaround to be able to use bionic nfs services. The idea is use official distribuiton packages instead
of shipping Debian packages with the release (which breaks the philosophy of a linux distribution and also the philosophy of Bosh)

For now it is focused on Ubuntu stemcells.


# Developing

Blobs of this release are stored in this git repository in the folder `blobstore`. The idea was taken from here: https://starkandwayne.com/blog/bosh-releases-with-git-lfs/

After this, files created by `bosh create-release --final` can be committed to the repo with git commit and it will be stored with git lfs. No need run `bosh sync-blobs`, instead just `git commit && git push`. All of these steps are automatically done by the script `create-final-public-release.sh`.

When do a git commit, try to use good commit messages; the release changes on each release will be taken from the commit messages!  

## Creating Dev releases (for testing)

To create a dev release -for testing purposes-, just run:

```
# Create a dev release
bosh  create-release --force --tarball=/tmp/release.tgz
# Upload release to bosh director
bosh -e <bosh-env> upload-release /tmp/release.tgz
```

Then you can modify your manifest to include `latest` as a version (no `url` and `sha` fields are needed when the release is manually uploaded): 

```
releases:
  [...]
- name: nfsclient
  version: latest
```

Once you know that the dev version is working, you can generate and publish a final version of the release (see  below), and remember to change the deployment manifest to use a url of the new final manifest like this:

```
releases:
  [...]
- name: nfsclient
  url: https://github.com/SpringerPE/nfsclient-boshrelease/releases/download/v8/nfsclient-8.tgz
  version: 8
  sha1: 12c34892f5bc99491c310c8867b508f1bc12629c
```

or much better, use an operations file ;-)


## Creating a new final release and publishing to GitHub releases:

Run: `./create-final-public-release.sh [version-number]`

Keep in mind you will need a Github token defined in a environment variable `GITHUB_TOKEN`. Please get your token here: https://help.github.com/articles/creating-an-access-token-for-command-line-use/
and run `export GITHUB_TOKEN="xxxxxxxxxxxxxxxxx"`, after that you can use the script.

`version-number` is optional. If not provided it will create a new major version (as integer), otherwise you can specify versions like "8.1", "8.1.2". There is a regular expresion in the script to check if the format is correct. Bosh client does not allow you to create 2 releases with the same version number. If for some reason you need to recreate a release version, delete the file created in `releases/nfsclient-boshrelease` and update the index file in the same location, you also need to remove the release (and tags) in Github.


# Usage in a deployment manifest

This is and add-on release, it will work only if it is deployed together with the 
*prometheus-boshrelease* on the nodes.

Considering v2 manifest style, add the new releases in the `releases` block:

```
releases:
  [...]
- name: nfsclient
  version: latest
```

then in your `instance_groups`, add:
 
```
instance_groups:
  [...]
  jobs:
  [...]
  - name: nfsclient
    release: nfsclient
```

# Author

SpringerNature Platform Engineering, José Riguera López (jose.riguera@springer.com)

Copyright 2017 Springer Nature


# License

Apache 2.0 License


# DiskImageDistribution

Tools to create and distribute macOS Applications through disk images. This consists of:

 - Script to build a disk image from an application, sign, and notarize it.
 - Sample background image for use in the disk image's Finder window.
 - Template to cusotmize background image using Affinity Designer.


## Script Usage

All parameters to the `make_disk_image.sh` script are provided through environment variables.

- `EXPANDED_CODE_SIGN_IDENTITY_NAME` - The team identity for code signing the disk image. This would need to be a _Developer ID_ identity.
- `APP_BUNDLE` – Path and name to the application bundle to package.
- `DISK_IMAGE_FULL_PATH` – Full path and file name of the resulting `.dmg` file.
- `APPLE_ID_MAIL` — The primary e-mail address of the Apple ID member of the team for use in notarization.
- `APPLE_ID_PASSWORD` – The [app-specific password](https://support.apple.com/en-us/HT204397) of the corresponding Apple ID for use in notarization
- `APPLE_ID_PROVIDER_SHORT_NAME` — (optional) the short name of the iTunes Provider for app store uploads. Only required if the Apple ID has access to more than uploading apps.
- `DISK_IMAGE_BACKGROUND_FILE` – (optional) name of `.png` image file that would be the disk image's background shown Finder.

Configure the above environment variables and simply run the script:

```bash
./BuildScripts/make_disk_image.sh
```

## Requirements

- Xcode 11.0
- Developer ID Account
- [create-dmg](https://github.com/andreyvit/create-dmg/releases)

## More Information

Refer to [Notarizing Disk Images for Developer ID Distribution](https://cutecoder.org/programming/notarize-disk-image-developer-id-distribution) for background information and details on how this script was put together.

## License

BSD 3-Clause License  
Copyright (c) 2019, Sasmito Adibowo  
https://cutecoder.org
All rights reserved.


## Usage
This script can be used to change a devices MAC address, hostname (and therefore also IP address). It supports several modes. Information is supplied in the `-h` option.

## Installation
1. Add this line to your .zshrc file:
`alias nmac='~/path/to/file/nmac.sh'`
2. Add the `.config` file to the folder of the script.
3. Add a `mac-vendors.csv` file to the same folder. Download from f.E. [maclookup.app](https://maclookup.app/downloads/csv-database)
4. (optional) Add a hostlist.txt file with custom hostnames to randomly choose from. Mandatory for `-m` option.

## Dependencies
This script has no further dependencies outside the macOS base system.

## License
This script is written by snw7 and licensed under the MIT License.
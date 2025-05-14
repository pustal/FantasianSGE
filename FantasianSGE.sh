#!/bin/bash

# FantasianSGE - Fantasian save game extractor
# Version 0.1.2
# Created by pustal
# Special thanks to uior, Xsonicdragon and Square_Ad1583 on Reddit for providing their data and helping debugging
# If this script is helpful to you, please consider buying me a Ko-Fi at https://ko-fi.com/pustal.

# Usage:
# - firstly check if you don't already have the root.json file in
# <Fantasian app>/Contents/Game/Data/_data (To explore the contents of the app and reach the save file,
# simply open Finder and go to you Applications folder, find Fantasian, right click and select 'Show Package Contents'
# - open the Terminal application;
# - navigate to whatever folder you have this script in, example (remove quotes):
# "cd ~/Downloads/";
# - type, without quotes, "chmod +x FantasianSGE.sh" to give the script execution permissions;
# - type, without quotes, "./FantasianSGE.sh" to execute the script;
# - you have now (re)created the root.json, the save file you should be importing to your Fantasian: Neo Dimensions machine;
# - in Windows, copy that file to "%USERPROFILE%/My Documents/My Games/FANTASIAN Neo Dimension/Steam/76561197991414426/_data"
# (it's possible that you'd need to start a new game first and play until you save it for the first time,
# so do that if it doesn't work right away and then copy and replace the file to said directory);
# - in Steam Play (Steam Deck / Linux), you'll have to navigate to a simillar directory inside
# <SteamLibrary-folder>/steamapps/compatdata/2844850/pfx/

DATABASE_HOMEPATH="~/Library/Containers/com.mistwalkercorp.fantasian/Data/Library/Application Support/FANTASIAN/SaveDataEntity.sqlite"
DATABASE_PATH="${DATABASE_HOMEPATH/#\~/$HOME}"
# If the line above doesn't work, place this script directly wherever the SaveDataEntity.sqlite file is
# and replace the line above with DATABASE_PATH="./SaveDataEntity.sqlite"
OUTPUT_FILE_PATH="./root.json"

echo Deleting old root.json file if it exists...
rm -f "$OUTPUT_FILE_PATH"

echo Extracting data from the game SQLite database...
sqlite3 "$DATABASE_PATH" <<EOF > temp_data.txt
.headers off
.mode csv
SELECT ZID, ZTIME, ZLOCALPLAYERNAME, ZDEVICENAME, ZUUID, HEX(ZDATA) FROM ZGAMEDATAENTITY;
EOF

echo  Reading extracted data...
IFS=',' read -r ZID ZTIME ZLOCALPLAYERNAME ZDEVICENAME ZUUID ZDATA_HEX < temp_data.txt

echo Convert hex to binary data...
echo "$ZDATA_HEX" | xxd -r -p > temp_data.bin

DATA_EXTRACTION_SCRIPT=$(cat << 'EOF'
import zlib
import sys
import json

input_file = sys.argv[1]
output_file = sys.argv[2]
zid = sys.argv[3]
ztime = sys.argv[4]
zlocalplayername = sys.argv[5]
zdevicename = sys.argv[6]
zuuid = sys.argv[7]

# (assuming ZTIME is seconds since epoch)
utc_ticks = int(float(ztime) * 10000000)

with open(input_file, 'rb') as f:
    compressed_data = f.read()

try:
    decompressed_data = zlib.decompress(compressed_data)
except zlib.error as e:
    print(f"Decompression error: {e}")
    sys.exit(1)

decompressed_string = decompressed_data.decode('utf-8')

root_json = {
    "path": zid,
    "utcTick": utc_ticks,
    "uuid": zuuid,
    "deviceName": zdevicename.strip('"'),
    "localPlayerName": zlocalplayername if zlocalplayername else "localPlayer",
    "dataString": decompressed_string
}

with open(output_file, 'w', encoding='utf-8') as f:
    json.dump(root_json, f, indent=4, ensure_ascii=False)

EOF
)

echo Extracting data...
python3 -c "$DATA_EXTRACTION_SCRIPT" temp_data.bin "$OUTPUT_FILE_PATH" "$ZID" "$ZTIME" "$ZLOCALPLAYERNAME" "$ZDEVICENAME" "$ZUUID"

echo Cleanig up...
rm temp_data.bin temp_data.txt

echo "root.json created and saved to $OUTPUT_FILE_PATH"

from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
files = [
    root / "src/drivers/storage/storage.h",
    root / "src/drivers/storage/nvMemory.cpp",
    root / "src/drivers/storage/SDCard.cpp",
    root / "src/drivers/displays/axehubCydDriver.cpp",
    root / "src/drivers/displays/axehubM5Driver.cpp",
    root / "src/drivers/displays/esp23_2432s028r.cpp",
]

bad_patterns = [
    r'String\("BC2"\)',
    r'==\s*"BC2"',
    r'!=\s*"BC2"',
    r'BC2_LOGO',
]

for path in files:
    text = path.read_text(encoding="utf-8")
    for pattern in bad_patterns:
        if re.search(pattern, text):
            raise AssertionError(f"{path.relative_to(root)} still contains BC2 fallback logic: {pattern}")

storage_header = (root / "src/drivers/storage/storage.h").read_text(encoding="utf-8")
if 'String CoinTicker{ "BTC" };' not in storage_header and 'String CoinTicker{"BTC"};' not in storage_header:
    raise AssertionError("storage default coin ticker is not BTC")

for path in [root / "src/drivers/storage/nvMemory.cpp", root / "src/drivers/storage/SDCard.cpp"]:
    text = path.read_text(encoding="utf-8")
    if 'Settings->CoinTicker = "BTC";' not in text:
        raise AssertionError(f"{path.relative_to(root)} does not normalize the coin ticker to BTC")
    if 'Settings->CoinTicker != "BTC"' not in text:
        raise AssertionError(f"{path.relative_to(root)} does not normalize legacy or non-BTC coin values")

print("coin default regression checks passed")

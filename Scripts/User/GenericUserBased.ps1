# This key will enablePrtSc keyboard key to run snipping tool
New-ItemProperty "HKCU:\Control Panel\Keyboard" -Name "PrintScreenKeyForSnippingEnabled" -PropertyType DWord -Value "1" -Force

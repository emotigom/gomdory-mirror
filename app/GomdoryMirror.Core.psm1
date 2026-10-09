Set-StrictMode -Version Latest

function ConvertFrom-AdbDevicesOutput {
    param([AllowEmptyString()][string]$OutputText)

    $devices = @()
    foreach ($line in ($OutputText -split "`r?`n")) {
        if ([string]::IsNullOrWhiteSpace($line) -or $line -like 'List of devices*' -or $line -like '*daemon*') { continue }

        $lineMatch = [regex]::Match($line, '^(?<serial>\S+)\s+(?<state>\S+)(?:\s+(?<details>.*))?$')
        if (-not $lineMatch.Success) { continue }

        $details = @{}
        foreach ($token in ($lineMatch.Groups['details'].Value -split '\s+')) {
            $tokenMatch = [regex]::Match($token, '^(?<key>[^:]+):(?<value>.*)$')
            if ($tokenMatch.Success) {
                $details[$tokenMatch.Groups['key'].Value] = $tokenMatch.Groups['value'].Value
            }
        }

        $serial = $lineMatch.Groups['serial'].Value
        $connectionType = if ($details.ContainsKey('usb')) { 'usb' } elseif ($serial -match ':\d+$') { 'wireless' } else { 'unknown' }
        $devices += [pscustomobject]@{
            Serial = $serial
            State = $lineMatch.Groups['state'].Value
            Model = if ($details.ContainsKey('model')) { $details['model'] -replace '_', ' ' } else { '' }
            Product = if ($details.ContainsKey('product')) { $details['product'] } else { '' }
            DeviceName = if ($details.ContainsKey('device')) { $details['device'] } else { '' }
            TransportId = if ($details.ContainsKey('transport_id')) { $details['transport_id'] } else { '' }
            ConnectionType = $connectionType
        }
    }

    return @($devices)
}

function ConvertFrom-AndroidGetPropOutput {
    param([AllowEmptyString()][string]$OutputText)

    $properties = @{}
    foreach ($line in ($OutputText -split "`r?`n")) {
        $propertyMatch = [regex]::Match($line, '^\[(?<key>[^]]+)\]:\s*\[(?<value>.*)\]$')
        if ($propertyMatch.Success) {
            $properties[$propertyMatch.Groups['key'].Value] = $propertyMatch.Groups['value'].Value
        }
    }
    return $properties
}

function Get-AndroidDeviceKind {
    param(
        [hashtable]$Properties,
        [AllowEmptyString()][string]$SizeOutput = '',
        [AllowEmptyString()][string]$DensityOutput = ''
    )

    $characteristics = if ($Properties.ContainsKey('ro.build.characteristics')) { [string]$Properties['ro.build.characteristics'] } else { '' }
    if ($characteristics -match '(^|,)tablet(,|$)') { return 'tablet' }
    if ($characteristics -match '(^|,)(watch|tv|automotive)(,|$)') { return 'other' }

    $sizeMatch = [regex]::Match($SizeOutput, '(?:Physical|Override) size:\s*(?<width>\d+)x(?<height>\d+)')
    $densityMatch = [regex]::Match($DensityOutput, '(?:Physical|Override) density:\s*(?<density>\d+)')
    if ($sizeMatch.Success -and $densityMatch.Success) {
        $shortPixels = [Math]::Min([int]$sizeMatch.Groups['width'].Value, [int]$sizeMatch.Groups['height'].Value)
        $density = [int]$densityMatch.Groups['density'].Value
        if ($density -gt 0) {
            $shortDp = $shortPixels * 160 / $density
            if ($shortDp -ge 600) { return 'tablet' }
            return 'phone'
        }
    }

    $model = if ($Properties.ContainsKey('ro.product.model')) { [string]$Properties['ro.product.model'] } else { '' }
    if ($model -match '(?i)(galaxy\s+tab|tablet|\btab\b|\bpad\b)') { return 'tablet' }
    return 'phone'
}

function Get-AndroidOemKey {
    param([AllowEmptyString()][string]$Manufacturer)

    switch -Regex ($Manufacturer.Trim()) {
        '(?i)samsung' { return 'samsung' }
        '(?i)google' { return 'google' }
        '(?i)(xiaomi|redmi|poco)' { return 'xiaomi' }
        '(?i)(lenovo|motorola)' { return 'lenovo-motorola' }
        '(?i)(oppo|oneplus|realme)' { return 'oppo-family' }
        '(?i)(huawei|honor)' { return 'huawei-honor' }
        '(?i)lg' { return 'lg' }
        '(?i)sony' { return 'sony' }
        '(?i)(asus|nvidia)' { return 'other' }
        default { return 'other' }
    }
}

Export-ModuleMember -Function ConvertFrom-AdbDevicesOutput, ConvertFrom-AndroidGetPropOutput, Get-AndroidDeviceKind, Get-AndroidOemKey

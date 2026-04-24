function Get-ExoOnlineStringBytes {
    param([string]$SizeString)

    # This exists because various exo cmdlets like to return a human readable string like "3.322 KB (3,402 bytes)" but not the raw bytes value
    
    if ($SizeString -match '\(([0-9,]+) bytes\)') {
        return [int64]($Matches[1] -replace ',','')
    }
    
    return 0
}

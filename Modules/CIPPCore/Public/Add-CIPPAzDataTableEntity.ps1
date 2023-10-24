function Add-CIPPAzDataTableEntity {
    [CmdletBinding()]
    param(
        $Context,
        $Entity,
        $Force,
        $CreateTableIfNotExists
    )
    
    foreach ($SingleEnt in $Entity) {
        try {
            # Attempt to add the entity to the data table
            Add-AzDataTableEntity @PSBoundParameters -Entity $SingleEnt
        }
        catch [System.Exception] {
            if ($_.Exception.ErrorCode -eq "PropertyValueTooLarge" -or $_.Exception.ErrorCode -eq "EntityTooLarge") {
                try {
                    # Maximum allowed size for a property in bytes (30KB)
                    $MaxSize = 30kb

                    # Identify which property in the hashtable is too large
                    $largePropertyName = $null
                    foreach ($key in $SingleEnt.Keys) {
                        if ($SingleEnt[$key].Length -gt $MaxSize) {
                            $largePropertyName = $key
                            break
                        }
                    }

                    if ($largePropertyName) {
                        $dataString = $SingleEnt[$largePropertyName]
                        $splitCount = [math]::Ceiling($dataString.Length / $MaxSize)
                        $splitData = 0..($splitCount - 1) | ForEach-Object {
                            $start = $_ * $MaxSize
                            $dataString.Substring($start, [Math]::Min($MaxSize, $dataString.Length - $start))
                        }

                        $splitPropertyNames = 1..$splitData.Count | ForEach-Object {
                            "${largePropertyName}_Part$_"
                        }

                        $splitInfo = @{
                            OriginalHeader = $largePropertyName;
                            SplitHeaders   = $splitPropertyNames
                        }
                        $SingleEnt["SplitOverProps"] = ($splitInfo | ConvertTo-Json).ToString()
                        $SingleEnt.Remove($largePropertyName)

                        for ($i = 0; $i -lt $splitData.Count; $i++) {
                            $SingleEnt[$splitPropertyNames[$i]] = $splitData[$i]
                        }

                        Add-AzDataTableEntity @PSBoundParameters -Entity $SingleEnt
                    }

                }
                catch {
                    throw "Error processing entity: $($_.Exception.Message)."
                }
            }
            else {
                throw $_
            }
        }
    }
}

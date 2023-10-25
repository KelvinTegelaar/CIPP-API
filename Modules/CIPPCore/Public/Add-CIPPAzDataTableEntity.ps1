function Add-CIPPAzDataTableEntity {
    [CmdletBinding()]
    param(
        $Context,
        $Entity,
        [switch]$Force,
        [switch]$CreateTableIfNotExists
    )
    
    foreach ($SingleEnt in $Entity) {
        try {
            Add-AzDataTableEntity -context $Context -force:$Force -CreateTableIfNotExists:$CreateTableIfNotExists -Entity $SingleEnt
        }
        catch [System.Exception] {
            if ($_.Exception.ErrorCode -eq "PropertyValueTooLarge" -or $_.Exception.ErrorCode -eq "EntityTooLarge") {
                try {
                    $MaxSize = 30kb
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

                        Add-AzDataTableEntity -context $Context -force:$Force -CreateTableIfNotExists:$CreateTableIfNotExists -Entity $SingleEnt
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

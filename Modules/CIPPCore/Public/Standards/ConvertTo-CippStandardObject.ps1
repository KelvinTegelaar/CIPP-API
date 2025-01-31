function ConvertTo-CippStandardObject {
    param(
        [Parameter(Mandatory = $true)]
        $StandardObject
    )
    if ($StandardObject -is [System.Collections.IEnumerable] -and -not ($StandardObject -is [string])) {
        $ProcessedItems = New-Object System.Collections.ArrayList
        foreach ($Item in $StandardObject) {
            $ProcessedItems.Add((Convert-SingleStandardObject $Item)) | Out-Null
        }
        return [System.Collections.ArrayList]$ProcessedItems
    } else {
        return Convert-SingleStandardObject $StandardObject
    }
}

function ConvertTo-CippStandardObject {

    param(
        [Parameter(Mandatory = $true)]
        $StandardObject
    )
    # If it's an array of items, process each item
    if ($StandardObject -is [System.Collections.IEnumerable] -and -not ($StandardObject -is [string])) {
        $ProcessedItems = New-Object System.Collections.ArrayList
        foreach ($Item in $StandardObject) {
            $ProcessedItems.Add((Convert-SingleStandardObject $Item)) | Out-Null
        }
        return $ProcessedItems
    } else {
        # Single object
        return Convert-SingleStandardObject $StandardObject
    }
}

function Clear-CIPPTestDataCache {
    <#
    .SYNOPSIS
        Clears the in-memory test data cache
    #>
    [CmdletBinding()]
    param()

    [CIPP.TestDataCache]::Clear()
}

function Get-CippErrorStatusCode {
    <#
    .SYNOPSIS
        Status code for a caught error: ArgumentException 400, ItemNotFoundException 404, anything else 500.
    .DESCRIPTION
        Helpers throw ArgumentException for invalid input or a refused request and ItemNotFoundException for
        a named resource that does not exist, so the calling endpoint can tell those apart from upstream failures.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$ErrorRecord
    )
    $Exception = if ($ErrorRecord -is [System.Management.Automation.ErrorRecord]) { $ErrorRecord.Exception } else { $ErrorRecord }
    while ($Exception) {
        if ($Exception -is [System.ArgumentException]) { return [System.Net.HttpStatusCode]::BadRequest }
        if ($Exception -is [System.Management.Automation.ItemNotFoundException]) { return [System.Net.HttpStatusCode]::NotFound }
        $Exception = $Exception.InnerException
    }
    [System.Net.HttpStatusCode]::InternalServerError
}

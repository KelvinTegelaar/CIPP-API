function Test-CIPPTableNotFound {
    <#
    .SYNOPSIS
    Returns true when an error indicates the Azure table does not exist.

    .DESCRIPTION
    Shared by the CIPP table entity wrappers so a stale CreateTable cache can self-heal on
    TableNotFound. Matches ErrorCode, HTTP 404 status, and the table service message text.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory, Position = 0)]
        $ErrorRecord
    )

    $Messages = [System.Collections.Generic.List[string]]::new()

    $Exceptions = [System.Collections.Generic.List[System.Exception]]::new()
    if ($ErrorRecord -is [System.Management.Automation.ErrorRecord]) {
        $Messages.Add([string]$ErrorRecord.FullyQualifiedErrorId)
        if ($ErrorRecord.Exception) { $Exceptions.Add($ErrorRecord.Exception) }
        if ($ErrorRecord.ErrorDetails -and $ErrorRecord.ErrorDetails.Message) {
            $Messages.Add([string]$ErrorRecord.ErrorDetails.Message)
        }
    } elseif ($ErrorRecord -is [System.Exception]) {
        $Exceptions.Add($ErrorRecord)
    } else {
        $Messages.Add([string]$ErrorRecord)
    }

    foreach ($Exception in $Exceptions) {
        $Current = $Exception
        while ($Current) {
            $Messages.Add([string]$Current.Message)
            $Messages.Add([string]$Current.GetType().FullName)

            foreach ($PropName in @('ErrorCode', 'Code', 'ErrorCodeString')) {
                $Prop = $Current.PSObject.Properties[$PropName]
                if ($Prop -and $Prop.Value) {
                    $Messages.Add([string]$Prop.Value)
                }
            }

            foreach ($PropName in @('Status', 'StatusCode', 'HttpStatusCode')) {
                $Prop = $Current.PSObject.Properties[$PropName]
                if ($Prop -and $null -ne $Prop.Value) {
                    $Status = $Prop.Value
                    if ($Status -is [enum]) { $Status = [int]$Status }
                    if ([string]$Status -eq '404' -or [int]$Status -eq 404) {
                        # 404 alone is not enough (blob/other resources), but with table context below.
                        $Messages.Add('HTTP404')
                    }
                }
            }

            $Current = $Current.InnerException
        }
    }

    foreach ($Message in $Messages) {
        if ([string]::IsNullOrWhiteSpace($Message)) { continue }
        if ($Message -match '(?i)TableNotFound|table specified does not exist') {
            return $true
        }
    }

    # RequestFailedException often exposes ErrorCode=TableNotFound; if we only saw HTTP 404 plus
    # table-ish wording elsewhere, the regex above already caught it.
    $false
}

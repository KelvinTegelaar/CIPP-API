using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"


# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."

# Lets get the DNS Module Helper
Import-Module ".\DNSHelper.psm1"

# Interact with query parameters or the body of the request.
$DomainToCheck = $Request.body.DomainToCheck
Write-Host "Domaintocheckpost: $($Request.body.DomainToCheck)"
$DomainToCheck = $DomainToCheck.TrimEnd('/')
$DomainToCheck = $DomainToCheck.Replace('https://','')
$DomainToCheck = $DomainToCheck.Replace('http://','')
$DomainToCheck = $DomainToCheck.Replace('www.','')
Write-Host "Final Domain to Test after Processing: $($DomainToCheck)"

$FinalObject = [PSCustomObject]@{
    DomainChecked = $DomainToCheck
    SPFResults = ""
    SPFPassCount = ""
    SPFWarnCount = ""
    SPFFailCount = ""
    SPFFinalState = ""
    DMARCResults = ""
    DMARCPassCount = ""
    DMARCWarnCount = ""
    DMARCFailCount = ""
    DMARCFinalState = ""
    MXResults = ""
    MXPassCount = ""
    MXWarnCount = ""
    MXFailCount = ""
    MXFinalState = ""
    DNSSECResults = ""
    DNSSECPassCount = ""
    DNSSECWarnCount = ""
    DNSSECFailCount = ""
    DNSSECFinalState = ""
    DKIMResults = ""
    DKIMPassCount = ""
    DKIMWarnCount = ""
    DKIMFailCount = ""
    DKIMFinalState = ""
}



try {
    $FinalObject.SPFResults = Read-SpfRecord -Domain $DomainToCheck
    $FinalObject.SPFPassCount = $FinalObject.SPFResults.ValidationPasses | Measure-Object | Select-Object -ExpandProperty Count
    $FinalObject.SPFWarnCount = $FinalObject.SPFResults.ValidationWarns | Measure-Object | Select-Object -ExpandProperty Count
    $FinalObject.SPFFailCount = $FinalObject.SPFResults.ValidationFails | Measure-Object | Select-Object -ExpandProperty Count
    if ($FinalObject.SPFFailCount -gt 0) {
        $FinalObject.SPFFinalState = 'Fail'
    }
    elseif ($FinalObject.SPFWarnCount -gt 0) {
        $FinalObject.SPFFinalState = 'Warn'
    }
    elseif ($FinalObject.SPFPassCount -gt 0) {
        $FinalObject.SPFFinalState = 'Pass'
    }
    else {
        $FinalObject.SPFFinalState = 'Unknown'
    }
}
catch {
    Log-Request -API $APINAME -tenant "CIPP" -user $request.headers.'x-ms-client-principal' -message "SPF Record Lookup Failed for $($DomainToCheck). $($_.Exception.Message)" -Sev "Error"
}

try {
    $FinalObject.DMARCResults = Read-DmarcPolicy -Domain $DomainToCheck
    $FinalObject.DMARCPassCount = $FinalObject.DMARCResults.ValidationPasses | Measure-Object | Select-Object -ExpandProperty Count
    $FinalObject.DMARCWarnCount = $FinalObject.DMARCResults.ValidationWarns | Measure-Object | Select-Object -ExpandProperty Count
    $FinalObject.DMARCFailCount = $FinalObject.DMARCResults.ValidationFails | Measure-Object | Select-Object -ExpandProperty Count
    if ($FinalObject.DMARCFailCount -gt 0) {
        $FinalObject.DMARCFinalState = 'Fail'
    }
    elseif ($FinalObject.DMARCWarnCount -gt 0) {
        $FinalObject.DMARCFinalState = 'Warn'
    }
    elseif ($FinalObject.DMARCPassCount -gt 0) {
        $FinalObject.DMARCFinalState = 'Pass'
    }
    else {
        $FinalObject.DMARCFinalState = 'Unknown'
    }
}
catch {
    Log-Request -API $APINAME -tenant "CIPP" -user $request.headers.'x-ms-client-principal' -message "DMARC Policy Lookup Failed for $($DomainToCheck). $($_.Exception.Message)" -Sev "Error"
}

try {
    $FinalObject.MXResults = Read-MXRecord -Domain $DomainToCheck
    $FinalObject.MXPassCount = $FinalObject.MXResults.ValidationPasses | Measure-Object | Select-Object -ExpandProperty Count
    $FinalObject.MXWarnCount = $FinalObject.MXResults.ValidationWarns | Measure-Object | Select-Object -ExpandProperty Count
    $FinalObject.MXFailCount = $FinalObject.MXResults.ValidationFails | Measure-Object | Select-Object -ExpandProperty Count
    if ($FinalObject.MXFailCount -gt 0) {
        $FinalObject.MXFinalState = 'Fail'
    }
    elseif ($FinalObject.MXWarnCount -gt 0) {
        $FinalObject.MXFinalState = 'Warn'
    }
    elseif ($FinalObject.MXPassCount -gt 0) {
        $FinalObject.MXFinalState = 'Pass'
    }
    else {
        $FinalObject.MXFinalState = 'Unknown'
    }
}
catch {
    Log-Request -API $APINAME -tenant "CIPP" -user $request.headers.'x-ms-client-principal' -message "MX Record Lookup Failed for $($DomainToCheck). $($_.Exception.Message)" -Sev "Error"
}

try {
    $FinalObject.DNSSECResults = Test-DNSSEC -Domain $DomainToCheck
    $FinalObject.DNSSECPassCount = $FinalObject.DNSSECResults.ValidationPasses | Measure-Object | Select-Object -ExpandProperty Count
    $FinalObject.DNSSECWarnCount = $FinalObject.DNSSECResults.ValidationWarns | Measure-Object | Select-Object -ExpandProperty Count
    $FinalObject.DNSSECFailCount = $FinalObject.DNSSECResults.ValidationFails | Measure-Object | Select-Object -ExpandProperty Count
    if ($FinalObject.DNSSECFailCount -gt 0) {
        $FinalObject.DNSSECFinalState = 'Fail'
    }
    elseif ($FinalObject.DNSSECWarnCount -gt 0) {
        $FinalObject.DNSSECFinalState = 'Warn'
    }
    elseif ($FinalObject.DNSSECPassCount -gt 0) {
        $FinalObject.DNSSECFinalState = 'Pass'
    }
    else {
        $FinalObject.DNSSECFinalState = 'Unknown'
    }
}
catch {
    Log-Request -API $APINAME -tenant "CIPP" -user $request.headers.'x-ms-client-principal' -message "DNSSEC Record Lookup Failed for $($DomainToCheck). $($_.Exception.Message)" -Sev "Error"
}

try {
    $FinalObject.DKIMResults = Read-DkimRecord -Domain $DomainToCheck
    $FinalObject.DKIMPassCount = $FinalObject.DKIMResults.ValidationPasses | Measure-Object | Select-Object -ExpandProperty Count
    $FinalObject.DKIMWarnCount = $FinalObject.DKIMResults.ValidationWarns | Measure-Object | Select-Object -ExpandProperty Count
    $FinalObject.DKIMFailCount = $FinalObject.DKIMResults.ValidationFails | Measure-Object | Select-Object -ExpandProperty Count
    if ($FinalObject.DKIMFailCount -gt 0) {
        $FinalObject.DKIMFinalState = 'Fail'
    }
    elseif ($FinalObject.DKIMWarnCount -gt 0) {
        $FinalObject.DKIMFinalState = 'Warn'
    }
    elseif ($FinalObject.DKIMPassCount -gt 0) {
        $FinalObject.DKIMFinalState = 'Pass'
    }
    else {
        $FinalObject.DKIMFinalState = 'Unknown'
    }
}
catch {
    Log-Request -API $APINAME -tenant "CIPP" -user $request.headers.'x-ms-client-principal' -message "DKIM Record Lookup Failed for $($DomainToCheck). $($_.Exception.Message)" -Sev "Error"
}

Write-Host "$DomainToCheck was checked with results:`nSPF Fails: $($FinalObject.SPFResults.ValidationFails)`nSPF Passes: $($FinalObject.SPFResults.ValidationPasses)`nSPF Warns: $($FinalObject.SPFResults.ValidationWarns) "
Write-Host "$DomainToCheck was checked with results:`nDMARC Fails: $($FinalObject.DMARCResults.ValidationFails)`nDMARC Passes: $($FinalObject.DMARCResults.ValidationPasses)`nDMARC Warns: $($FinalObject.DMARCResults.ValidationWarns) "
Write-Host "$DomainToCheck was checked with results:`nDKIM Fails: $($FinalObject.DKIMResults.ValidationFails)`nDKIM Passes: $($FinalObject.DKIMResults.ValidationPasses)`nDKIM Warns: $($FinalObject.DKIMResults.ValidationWarns) "


# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = @($FinalObject)
    })

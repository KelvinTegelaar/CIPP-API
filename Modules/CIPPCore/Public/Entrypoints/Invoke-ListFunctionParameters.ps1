using namespace System.Net

function Invoke-ListFunctionParameters {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Core.Read
    #>
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    # Write to the Azure Functions log stream.
    Write-Information 'PowerShell HTTP trigger function processed a request.'

    # Interact with query parameters or the body of the request.
    $Module = $Request.Query.Module
    $Function = $Request.Query.Function

    $CommandQuery = @{}
    if ($Module) {
        $CommandQuery.Module = $Module
    }
    if ($Function) {
        $CommandQuery.Name = $Function
    }
    $IgnoreList = 'entryPoint', 'internal'
    $CommonParameters = @('Verbose', 'Debug', 'ErrorAction', 'WarningAction', 'InformationAction', 'ErrorVariable', 'WarningVariable', 'InformationVariable', 'OutVariable', 'OutBuffer', 'PipelineVariable', 'TenantFilter', 'APIName', 'ExecutingUser', 'ProgressAction', 'WhatIf', 'Confirm')
    $TemporaryBlacklist = 'Get-CIPPAuthentication', 'Invoke-CippWebhookProcessing', 'Invoke-ListFunctionParameters', 'New-CIPPAPIConfig', 'New-CIPPGraphSubscription'
    try {
        if ($Module -eq 'ExchangeOnlineManagement') {
            $ExoRequest = @{
                AvailableCmdlets = $true
                tenantid         = $env:TenantID
                NoAuthCheck      = $true
            }
            if ($Request.Query.Compliance -eq $true) {
                $ExoRequest.Compliance = $true
            }
            $Functions = New-ExoRequest @ExoRequest
            Write-Host $Functions
        } else {
            $Functions = Get-Command @CommandQuery | Where-Object { $_.Visibility -eq 'Public' }
        }
        $Results = foreach ($Function in $Functions) {
            if ($Function -In $TemporaryBlacklist) { continue }
            $GetHelp = @{
                Name = $Function
            }
            if ($Module -eq 'ExchangeOnlineManagement') {
                $GetHelp.Path = 'ExchangeOnlineHelp'
            }
            $Help = Get-Help @GetHelp
            $ParamsHelp = ($Help | Select-Object -ExpandProperty parameters).parameter | Select-Object name, @{n = 'description'; exp = { $_.description.Text } }
            if ($Help.Functionality -in $IgnoreList) { continue }
            $Parameters = foreach ($Key in $Function.Parameters.Keys) {
                if ($CommonParameters -notcontains $Key) {
                    $Param = $Function.Parameters.$Key
                    $ParamHelp = $ParamsHelp | Where-Object { $_.name -eq $Key }
                    [PSCustomObject]@{
                        Name        = $Key
                        Type        = $Param.ParameterType.FullName
                        Description = $ParamHelp.description
                        Required    = $Param.Attributes.Mandatory
                    }
                }
            }
            [PSCustomObject]@{
                Function   = $Function.Name
                Synopsis   = $Help.Synopsis
                Parameters = @($Parameters)
            }
        }
        $StatusCode = [HttpStatusCode]::OK
        $Results
    } catch {
        $Results = "Function Error: $($_.Exception.Message)"
        $StatusCode = [HttpStatusCode]::BadRequest
    }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($Results)
        })

}

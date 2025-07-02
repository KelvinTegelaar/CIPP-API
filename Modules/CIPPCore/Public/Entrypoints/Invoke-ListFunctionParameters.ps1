using namespace System.Net

function Invoke-ListFunctionParameters {
    <#
    .SYNOPSIS
    List function parameters and documentation for CIPP modules
    
    .DESCRIPTION
    Retrieves function parameters, types, descriptions, and documentation for CIPP modules including Exchange Online Management.
    
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.Core.Read
        
    .NOTES
    Group: Development
    Summary: List Function Parameters
    Description: Retrieves detailed function information including parameters, types, descriptions, and documentation for CIPP modules and Exchange Online Management cmdlets.
    Tags: Development,Documentation,Parameters
    Parameter: Module (string) [query] - Module name to list functions from (e.g., 'ExchangeOnlineManagement')
    Parameter: Function (string) [query] - Specific function name to get parameters for
    Parameter: Compliance (boolean) [query] - Whether to include compliance cmdlets for Exchange Online Management
    Response: Returns an array of function objects with the following properties:
    Response: - Function (string): Function name
    Response: - Synopsis (string): Function synopsis from help documentation
    Response: - Parameters (array): Array of parameter objects with the following properties:
    Response: - Name (string): Parameter name
    Response: - Type (string): Parameter type (full .NET type name)
    Response: - Description (string): Parameter description from help documentation
    Response: - Required (boolean): Whether the parameter is mandatory
    Example: [
      {
        "Function": "Get-CIPPUser",
        "Synopsis": "Retrieves user information from Microsoft 365",
        "Parameters": [
          {
            "Name": "UserID",
            "Type": "System.String",
            "Description": "User ID or email address to retrieve",
            "Required": true
          },
          {
            "Name": "TenantFilter",
            "Type": "System.String",
            "Description": "Tenant to query",
            "Required": false
          }
        ]
      }
    ]
    Error: Returns error details if the operation fails to retrieve function parameters.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

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
    $CommonParameters = @('Verbose', 'Debug', 'ErrorAction', 'WarningAction', 'InformationAction', 'ErrorVariable', 'WarningVariable', 'InformationVariable', 'OutVariable', 'OutBuffer', 'PipelineVariable', 'TenantFilter', 'APIName', 'Headers', 'ProgressAction', 'WhatIf', 'Confirm', 'Headers', 'NoAuthCheck')
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
            #Write-Host $Functions
        }
        else {
            $Functions = Get-Command @CommandQuery | Where-Object { $_.Visibility -eq 'Public' }
        }
        $Results = foreach ($Function in $Functions) {
            if ($Function -in $TemporaryBlacklist) { continue }
            $GetHelp = @{
                Name = $Function
            }
            if ($Module -eq 'ExchangeOnlineManagement') {
                $GetHelp.Path = 'ExchangeOnlineHelp'
            }
            $Help = Get-Help @GetHelp
            $ParamsHelp = ($Help | Select-Object -ExpandProperty parameters).parameter | Select-Object name, @{n = 'description'; exp = { $_.description.Text } }
            if ($Help.Functionality -in $IgnoreList) { continue }
            if ($Help.Functionality -match 'Entrypoint') { continue }
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
    }
    catch {
        $Results = "Function Error: $($_.Exception.Message)"
        $StatusCode = [HttpStatusCode]::BadRequest
    }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($Results)
        })

}

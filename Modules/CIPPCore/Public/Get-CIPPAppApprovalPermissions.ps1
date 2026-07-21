function Get-CIPPAppApprovalPermissions {
    <#
    .SYNOPSIS
        Resolves the effective permissions for an App Approval template.
    .DESCRIPTION
        App Approval templates persist a copy of the permission set at the time the template was saved.
        That copy goes stale the moment the linked permission set is edited, so when a template links to
        a permission set the set is treated as the source of truth. Templates without a PermissionSetId
        (older or hand-built ones) fall back to the copy stored on the template.
    .PARAMETER TemplateId
        RowKey of the AppApprovalTemplate to resolve.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TemplateId
    )

    $TemplateTable = Get-CIPPTable -TableName 'templates'
    $Filter = "RowKey eq '$TemplateId' and PartitionKey eq 'AppApprovalTemplate'"
    $Template = (Get-CIPPAzDataTableEntity @TemplateTable -Filter $Filter).JSON | ConvertFrom-Json -ErrorAction SilentlyContinue

    if (!$Template) {
        Write-Information "App approval template $TemplateId not found"
        return $null
    }

    $Permissions = $Template.Permissions

    if ($Template.PermissionSetId) {
        $PermissionsTable = Get-CIPPTable -TableName 'AppPermissions'
        $SetFilter = "PartitionKey eq 'Templates' and RowKey eq '$($Template.PermissionSetId)'"
        $PermissionSet = Get-CIPPAzDataTableEntity @PermissionsTable -Filter $SetFilter

        if ($PermissionSet.Permissions) {
            $SetPermissions = $PermissionSet.Permissions | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($SetPermissions) {
                $Permissions = $SetPermissions
            } else {
                Write-Information "Permission set $($Template.PermissionSetId) for template $TemplateId could not be parsed, falling back to the permissions stored on the template"
            }
        } else {
            Write-Information "Permission set $($Template.PermissionSetId) for template $TemplateId not found, falling back to the permissions stored on the template"
        }
    }

    return [PSCustomObject]@{
        ApplicationId = $Template.AppId
        Permissions   = $Permissions
    }
}

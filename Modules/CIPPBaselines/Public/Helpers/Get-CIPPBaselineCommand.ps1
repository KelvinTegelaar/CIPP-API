function Get-CIPPBaselineCommand {
    <#
    .SYNOPSIS
        Looks up one command by its exact name, or returns nothing.
    .DESCRIPTION
        Get-Command resolves name patterns and copies the whole session function table on every call; the baseline
        engine asks for a collector, prepare hook or executor for every standard it grades. This is a direct lookup.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Name)

    $ExecutionContext.InvokeCommand.GetCommand($Name, [System.Management.Automation.CommandTypes]'Function, Cmdlet, Alias')
}

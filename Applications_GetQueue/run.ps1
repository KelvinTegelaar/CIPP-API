param($name)

$object = (Get-ChildItem ".\ChocoApps.Cache\*" | Where-Object { $_.name -ne "CurrentlyRunning.txt" }).name 
$object
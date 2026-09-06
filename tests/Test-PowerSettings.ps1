#requires -Version 5.1
$ErrorActionPreference = 'Stop'
$tokens=$null; $errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot '..\Set-ZenithStyle.ps1'),[ref]$tokens,[ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
foreach ($name in @('Test-PowerEntry','Get-PowerTarget','Test-PowerValue','Read-Value','Set-LidValue')) {
    $fn=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
    . ([scriptblock]::Create($fn.Extent.Text))
}
$script:calls=@()
$script:fixture=''
function Invoke-PowerCfg($Arguments) {
    $script:calls+=,$Arguments
    if ($Arguments[0] -eq '/qh') { return $script:fixture }
}
function Get-ActiveScheme { '11111111-2222-3333-4444-555555555555' }
function Assert($Condition,$Message) { if (-not $Condition) { throw $Message } }
$path='PowerPlan:11111111-2222-3333-4444-555555555555'
foreach ($case in @(
    @{Name='AC';Fixture='AC 0x00000001 DC 0x00000002';Value=1;Sub='SUB_BUTTONS';Setting='LIDACTION'},
    @{Name='DC';Fixture='AC 0x00000001 DC 0x00000002';Value=2;Sub='SUB_BUTTONS';Setting='LIDACTION'},
    @{Name='AC_SLEEP';Fixture='min 0x00000000 max 0xffffffff step 0x00000001 AC 0x0000012c DC 0x000000b4';Value=300;Sub='SUB_SLEEP';Setting='STANDBYIDLE'},
    @{Name='AC_DISPLAY';Fixture='min 0x00000000 max 0xffffffff step 0x00000001 AC 0x00000258 DC 0x000000b4';Value=600;Sub='SUB_VIDEO';Setting='VIDEOIDLE'}
)) {
    $script:fixture=$case.Fixture
    Assert ((Read-Value $path $case.Name).Value -eq $case.Value) 'Power index parsing failed'
    $script:calls=@()
    Set-LidValue $path $case.Name $case.Value
    $expectedOption=if ($case.Name -eq 'DC') { '/setdcvalueindex' } else { '/setacvalueindex' }
    Assert ($script:calls[0][0] -eq $expectedOption -and $script:calls[0][2] -eq $case.Sub -and $script:calls[0][3] -eq $case.Setting -and $script:calls[0][4] -eq [string]$case.Value) 'Wrong powercfg write arguments'
    Assert ($script:calls.Count -eq 2 -and $script:calls[1][0] -eq '/setactive') 'Active plan was not refreshed'
}
$script:fixture='unrecognized output'
$rejected=$false
try { Read-Value $path 'AC_SLEEP' | Out-Null } catch { $rejected=$true }
Assert $rejected 'Malformed output accepted'
foreach ($value in @(-1,4294967296,'invalid')) { Assert (-not (Test-PowerValue 'AC_SLEEP' $value)) 'Invalid timeout accepted' }
Assert (Test-PowerValue 'AC_SLEEP' ([uint32]::MaxValue)) 'Valid unsigned timeout rejected'
function Get-ActiveScheme { 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' }
$script:calls=@()
Set-LidValue $path 'AC_DISPLAY' 600
Assert ($script:calls.Count -eq 1) 'Restoring an inactive plan switched active plans'
Write-Output 'PASS: real power parsing and command construction with mocked powercfg; malformed values and inactive-plan restore'

# -----------------------------------------------------------------------------
# Author: mbl35
#
#  This is a PowerShell wrapper around the inbuilt WSL CLI.
#  It simplifies the calls to wsl, by just allowing you to call commands with
#  a simple "wslctl" call.
#  Best used with the path to the script in your PATH.
# -----------------------------------------------------------------------------

using module ".\Application\ServiceLocator.psm1"
using module ".\Application\AppConfig.psm1"
using module ".\Application\ControllerManager.psm1"

using module ".\Service\BuilderService.psm1"
using module ".\Service\RegistryService.psm1"
using module ".\Service\BackupService.psm1"
using module ".\Service\WslService.psm1"

using module ".\Controller\DefaultController.psm1"
using module ".\Controller\BackupController.psm1"
using module ".\Controller\RegistryController.psm1"


$version = "2.1.0"

[ServiceLocator]::getInstance().add( 'config', [AppConfig]::new($version) )
[ServiceLocator]::getInstance().add( 'registry', [RegistryService]::new() )
[ServiceLocator]::getInstance().add( 'backup', [BackupService]::new() )
[ServiceLocator]::getInstance().add( 'builder', [BuilderService]::new() )
[ServiceLocator]::getInstance().add( 'wsl-wrapper', [WslService]::new() )



[ControllerManager]::new(@(
    [DefaultController]::new(),
    [BackupController]::new(),
    [RegistryController]::new()
)).run( $args )

exit $LastExitCode

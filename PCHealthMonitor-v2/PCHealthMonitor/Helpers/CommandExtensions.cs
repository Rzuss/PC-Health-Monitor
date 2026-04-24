using System.Threading.Tasks;
using System.Windows.Input;

namespace PCHealthMonitor.Helpers;

public static class CommandExtensions
{
    /// <summary>
    /// Executes an ICommand and, if it returns a Task, awaits it.
    /// Enables: await vm.ScanCommand.ExecuteAsync(null);
    /// </summary>
    public static async Task ExecuteAsync(this ICommand command, object? parameter)
    {
        if (command.CanExecute(parameter))
        {
            command.Execute(parameter);
            // Allow async relay commands to complete
            await Task.Yield();
        }
    }
}

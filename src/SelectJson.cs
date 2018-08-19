using System;
using System.Management.Automation;
using DevLab.JmesPath;

namespace JMES.PS
{   
    [Cmdlet(VerbsCommon.Select, "JSON")]
    public class SelectJSONCommand : PSCmdlet
    {
        [Parameter(Mandatory = true, ValueFromPipelineByPropertyName = true, Position = 1)]
        public string JMESPath { get; set; } = string.Empty;

        [Parameter(Mandatory = true, ValueFromPipeline = true, ValueFromPipelineByPropertyName = true, Position = 2)]
        public string Content { get; set; } = string.Empty;

        protected override void BeginProcessing()
        {

        }

        protected override void ProcessRecord()
        {
            var jmes = new JmesPath();
            var result = jmes.Transform(json: Content, expression: JMESPath);
            WriteObject(result);
        }

        protected override void EndProcessing()
        {
            // string timestamp = DateTime.Now.ToString("u");
            // this.WriteObject($"[{timestamp}] - {this.JMESPath}");
            // base.EndProcessing();
        }
    }
}

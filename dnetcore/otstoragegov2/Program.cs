using System;
using System.IO;
using System.Threading.Tasks;
using Microsoft.Azure.Storage;
using Microsoft.Azure.Storage.Blob;
using Microsoft.Azure.Storage.Auth;
using Microsoft.Extensions.Configuration;

namespace otstoragegov2
{
    class Program
    {
        public static async Task Main()
        {
            Console.WriteLine("Azure Blob Storage - .NET quickstart sample\n");         
            
            await ProcessAsync();

            Console.WriteLine("Press any key to exit the sample application.");
            Console.ReadLine();
        }
        private static async Task ProcessAsync()
        {
            string _accountSAS = @"";
            string _accountName = "gtexstgsasss";
            string _endpointSuffix = "core.usgovcloudapi.net";
            string _blobStorageContainer = "sas";
            //string file1 = Configuration["file1"];
            string remoteFilename = "folder1/" + "Microsoft.WindowsAzure.Storagecore2.dll";                   
            StorageCredentials _sc = new StorageCredentials(_accountSAS);
            CloudStorageAccount _storageAccount = new CloudStorageAccount(_sc, _accountName, _endpointSuffix, true);
            CloudBlobClient _cloudBlob = _storageAccount.CreateCloudBlobClient();
            CloudBlobContainer  _blobContainer = _cloudBlob.GetContainerReference(_blobStorageContainer);
            _blobContainer.CreateIfNotExists();
            CloudBlockBlob azureBlockBlob = _blobContainer.GetBlockBlobReference(remoteFilename);
            Stream stream = File.OpenRead(@"");
            await azureBlockBlob.UploadFromStreamAsync(stream, AccessCondition.GenerateIfNotExistsCondition(),
                                                new BlobRequestOptions { ParallelOperationThreadCount = 2 },
                                                new OperationContext()).ConfigureAwait(false);
            Console.WriteLine("Upload completed!"); 
        }
    }
}

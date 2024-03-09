// main template for insights-mimir
local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();

// The hiera parameters for the component
local params = inv.parameters.mimir;

// Namespace
local namespace = kube.Namespace(params.namespace.name) {
  metadata: {
    [if std.length(params.namespace.annotations) > 0 then 'annotations']: params.namespace.annotations,
    labels: {
      'app.kubernetes.io/name': params.namespace.name,
      'app.kubernetes.io/managed-by': 'commodore',
      'pod-security.kubernetes.io/enforce': 'baseline',
      'pod-security.kubernetes.io/warn': 'restricted',
      'pod-security.kubernetes.io/audit': 'restricted',
    } + com.makeMergeable(params.namespace.labels),
    name: params.namespace.name,
  },
};

// Bucket Claims
local objectbucket = kube._Object('objectbucket.io/v1alpha1', 'ObjectBucketClaim', params.s3.bucket) {
  metadata: {
    labels: {
      'app.kubernetes.io/name': params.s3.bucket,
      'app.kubernetes.io/instance': 'mimir',
      'app.kubernetes.io/managed-by': 'commodore',
    },
    namespace: params.namespace.name,
    name: params.s3.bucket,
  },
  spec: {
    bucketName: params.s3.bucket,
    storageClassName: params.global.objectClass,
  },
};

// Secrets
// local basicauth = kube._Object('', '', '')

// Define outputs below
{
  '00_namespace': namespace,
  '20_objectbucket': objectbucket,
}

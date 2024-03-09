local kap = import 'lib/kapitan.libjsonnet';
local inv = kap.inventory();
local params = inv.parameters.mimir;
local argocd = import 'lib/argocd.libjsonnet';

local app = argocd.App('mimir', params.namespace.name);

{
  mimir: app {
    spec+: {
      syncPolicy+: {
        syncOptions+: [
          'ServerSideApply=true',
        ],
      },
      ignoreDifferences: [ {
        group: 'apps',
        kind: 'StatefulSet',
        jsonPointers: [
          '/spec/volumeClaimTemplates/0/apiVersion',
          '/spec/volumeClaimTemplates/0/kind',
        ],
      } ],
    },
  },
}

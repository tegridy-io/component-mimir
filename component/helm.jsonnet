local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local inv = kap.inventory();

// The hiera parameters for the component
local params = inv.parameters.mimir;

// Zone Aware Replication
local zoneAwareReplication = {
  enabled: params.global.zoneAwareReplication,
  zones: [
    { name: 'zone-a', nodeSelector: params.global.nodeSelector },
    { name: 'zone-b', nodeSelector: params.global.nodeSelector },
    { name: 'zone-c', nodeSelector: params.global.nodeSelector },
  ],
};

// Topology Spread Constaints
local topologySpreadConstraints = {
  maxSkew: 1,
  topologyKey: 'kubernetes.io/hostname',
  whenUnsatisfiable: 'DoNotSchedule',
};

// Values Files
local components = com.makeMergeable({
  // Read Path
  querier: {
    nodeSelector: params.global.nodeSelector,
    topologySpreadConstraints: topologySpreadConstraints,
  } + com.makeMergeable(params.components.querier),
  query_frontend: {
    nodeSelector: params.global.nodeSelector,
    topologySpreadConstraints: topologySpreadConstraints,
  } + com.makeMergeable(params.components.queryFrontend),
  store_gateway: {
    nodeSelector: params.global.nodeSelector,
    topologySpreadConstraints: topologySpreadConstraints,
    persistentVolume: {
      storageClass: params.global.storageClass,
    },
    zoneAwareReplication: zoneAwareReplication,
  } + com.makeMergeable(params.components.storeGateway),
  // Write Path
  distributor: {
    nodeSelector: params.global.nodeSelector,
    topologySpreadConstraints: topologySpreadConstraints,
  } + com.makeMergeable(params.components.distributor),
  ingester: {
    nodeSelector: params.global.nodeSelector,
    topologySpreadConstraints: topologySpreadConstraints,
    persistentVolume: {
      storageClass: params.global.storageClass,
    },
    zoneAwareReplication: zoneAwareReplication,
  } + com.makeMergeable(params.components.ingester),
  // Backend
  compactor: {
    nodeSelector: params.global.nodeSelector,
    topologySpreadConstraints: topologySpreadConstraints,
    persistentVolume: {
      storageClass: params.global.storageClass,
    },
  } + com.makeMergeable(params.components.compactor),
  // overrides_exporter: {
  //   nodeSelector: params.global.nodeSelector,
  // } + com.makeMergeable(params.components.overridesExporter),
  // rollout_operator: {
  //   nodeSelector: params.global.nodeSelector,
  // } + com.makeMergeable(params.components.rolloutOperator),
  // Ingress Configuration
  gateway: {
    enabledNonEnterprise: true,
    nodeSelector: params.global.nodeSelector,
    topologySpreadConstraints: topologySpreadConstraints,
  },
});

// Caches
local caches = com.makeMergeable({
  'chunks-cache': {
    nodeSelector: params.global.nodeSelector,
    topologySpreadConstraints: topologySpreadConstraints,
  } + com.makeMergeable(params.caches.chunks),
  'index-cache': {
    nodeSelector: params.global.nodeSelector,
    topologySpreadConstraints: topologySpreadConstraints,
  } + com.makeMergeable(params.caches.index),
  'metadata-cache': {
    nodeSelector: params.global.nodeSelector,
    topologySpreadConstraints: topologySpreadConstraints,
  } + com.makeMergeable(params.caches.metadata),
  'results-cache': {
    nodeSelector: params.global.nodeSelector,
    topologySpreadConstraints: topologySpreadConstraints,
  } + com.makeMergeable(params.caches.results),
});

// Optional components
local optional = com.makeMergeable({
  alertmanager: {
    nodeSelector: params.global.nodeSelector,
    topologySpreadConstraints: topologySpreadConstraints,
    persistentVolume: {
      storageClass: params.global.storageClass,
    },
  } + com.makeMergeable(params.optional.alertmanager),
  query_scheduler: {
    nodeSelector: params.global.nodeSelector,
    topologySpreadConstraints: topologySpreadConstraints,
  } + com.makeMergeable(params.optional.queryScheduler),
  ruler: {
    nodeSelector: params.global.nodeSelector,
    topologySpreadConstraints: topologySpreadConstraints,
  } + com.makeMergeable(params.optional.ruler),
});

// Bucket Config
local bucketOBC = com.makeMergeable({
  mimir: {
    structuredConfig: {
      common: {
        storage: {
          backend: 's3',
          s3: {
            access_key_id: '${AWS_ACCESS_KEY_ID}',
            secret_access_key: '${AWS_SECRET_ACCESS_KEY}',
          },
        },
      },
    },
  },
  global: {
    extraEnvFrom: [
      { secretRef: { name: params.s3.bucket } },
    ],
  },
});

local bucket = if params.s3.mode == 'obc' then
  bucketOBC
else
  {};

// HA Tracker
local haTracker = com.makeMergeable({
  mimir: {
    structuredConfig+: {
      limits: {
        accept_ha_samples: true,
        ha_cluster_label: params.config.haLabels.cluster,
        ha_replica_label: params.config.haLabels.replica,
      },
      distributor: {
        ha_tracker: {
          enable_ha_tracker: true,
          ha_tracker_failover_timeout: '60s',
          kvstore: {
            store: params.config.haStore.type,
            [params.config.haStore.type]: {
              [obj]: params.config.haStore[obj]
              for obj in std.objectFields(params.config.haStore)
              if obj != 'type'
            },
          },
        },
      },
    },
  },
});

// Mimir Config
local mimir = {
  mimir: {
    structuredConfig: {
      common: {
        storage: {
          backend: 's3',
          s3: {
            bucket_name: params.s3.bucket,
            endpoint: params.s3.endpoint,
            region: params.s3.region,
            insecure: params.s3.insecure,
          },
        },
      },
      tenant_federation: {
        enabled: params.config.tenantFederation,
      },
      ruler: {
        tenant_federation: {
          enabled: params.config.tenantFederation,
        },
      },
    },
  },
  [if params.ingress.enabled then 'gateway']: {
    ingress: {
      enabled: true,
      annotations: params.ingress.annotations,
      hosts: [ {
        host: params.ingress.url,
        paths: [ {
          path: '/',
          pathType: 'Prefix',
        } ],
      } ],
      tls: [ {
        secretName: 'mimir-gateway-tls',
        hosts: [ params.ingress.url ],
      } ],
    },
    nginx: {
      verboseLogging: false,
      // basicAuth: {
      //   enabled: true,
      //   htpasswd: '',
      // },
    },
  },
};

// local configs = if params.s3.shared_bucket then configsSharedBucket else configsSingleBucket;

{
  ['%s-components' % inv.parameters._instance]: components + optional + caches,
  ['%s-configs' % inv.parameters._instance]: mimir + bucket + haTracker,
  ['%s-overrides' % inv.parameters._instance]: params.helmValues,
}

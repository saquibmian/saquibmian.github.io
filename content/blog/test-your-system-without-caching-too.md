+++
date = "2017-05-13T11:23:45-04:00"
draft = false
title = "Test your system without caching, too"
tags = ["caching", "resiliency"]
description = "Designing your system around stellar cache performance is almost certainly going to have you paged in the middle of the night. Make sure you test cache failure scenarios, and isolate your system to degrade gracefully."
+++

>The most severe outages at Twitter were cache outages.
>
>-Yao Yue (Engineer at Twitter)

This blog post is based on some of the ideas in Yao Yue’s [talk at QConSF](https://www.infoq.com/presentations/pelikan) last year, which I had the opportunity to attend, and some of the discussions I’ve heard at work recently.

When we usually think about caching, we realize pretty quickly that cache invalidation is [difficult to get right](https://martinfowler.com/bliki/TwoHardThings.html). You have to be careful to invalidate correctly, in the correct order, and avoid race conditions in cache PUTs. But we put a lot of effort into utilizing a cache because of the benefits it gives us: decreased load on our databases and a performance boost via super fast in-memory lookups. Indeed, caching is critical to a high performing service.

But there’s something else that developers often forget, because traditionally this has been a ops problem: what happens to your application when your cache thrashes or falls over? Ephemeral/occasional spikes in response times that are very difficult to explain.

Imagine you’ve architected a well-designed domain and you’ve spent a lot of time making sure that your service is elastic and that you’re using your cache effectively. Objects in your domain have reproducible, domain-intrinsic cache keys, so when new servers enter the load, they can immediately make use of the cache and start serving requests. Like any good developer, you cache All The Things and have tweaked your TTLs and data models to achieve a 99% hit ratio. You even use MULTIGET to cache collections. You’re in nirvana. Therein lies the problem.

When your cache hit ratio is 99%, a _single percentage point drop_ to 98% results in _double_ the amount of load on your database. Pause for a second and really let that sink in.

It’s incredibly easy to rely heavily on caching and under provision your databases, and when your cache servers inevitably fall over/suffer a network partition/thrash, your application either slows down to a crawl (because you hadn’t considered putting timeouts around cache GETs or SETs and memcached can’t keep up, or your database is on fire), or your application completely falls over (because you didn't have back-off and ran out of threads/memory/etc. due to queued requests, or because your domain involves transforming the data before doing a cache PUT and now you're out of compute). In both cases, you application probably will not degrade gracefully.

Even worse is that recovering from a cache incident is not trivial because of connection storm and the problem of thundering herds. **Connection storm** is when a service comes back online or is put into a pool and is subsequently “stormed” with many many clients (re)connecting to it, or when a large group of services come online and connect to a common service at roughly the same time (yet another reason to use a scheduler with gradual service rollout). This has traditionally been a huge problem with memcached, which is single threaded and incurs significant overhead in accepting new connections.
Similarly, **thundering herds** (the caching one, not the [OS one](http://uwsgi-docs.readthedocs.io/en/latest/articles/SerializingAccept.html)) is when a single key experiences a large amount of read and write activity, making reads expensive as the key is invalidated often, and this happens often at hit rates below 92% (I couldn't find my reference for this, but it's reasonable to intuit).

Don’t be lulled into relying on your cache servers heavily. Achieving a 99% hit rate isn’t as great as you might think; it’s far more important that your application behave _consistently_ and _predictably_. Here are some techniques people have used to solve this:

1. Run game day scenarios where you kill random cache servers. Study the behaviour of your application and your databases when you do this, and allocate resources appropriately. Knowledge is foresight.
2. Kill random cache servers periodically in production, and do this often. This will bring the pain forward, and will force you to not under-provision that database server accidentally or to consider how you might degrade gracefully instead of going to the database at all. Remember that your database is not elastic and needs reserve capacity (unlike other things, it generally should not run hot).
3. Put timeouts and cancellations around all cache interactions. If it takes longer to GET something from cache than it does to fetch that same thing from your database, you might have succeeded in keeping load off of the database, but the person waiting for a response is not very happy with you [[0]](#0). Similarly, when cache servers thrash, a SET becomes quite expensive, as it can't complete until enough data blocks are free, and there's usually a long queue of other entries waiting for be SET first. Putting timeouts and cancellations around cache interactions makes it easier for cache servers to recover in the event of a catastrophe by deciding to avoid the cache server until it heals.
4. Prevent fan-in to your cache servers. Deploy cache proxies [[1]](#1) in front of a pool of cache servers, to avoid connection storm (and make sure to use consistent hashing).
5. Consider co-locating your cache servers. Running your in-memory cache on the same machine as your server, or as a side car container [[2]](#2), eliminates network partitions as a source of failure, but also significantly increases your memory requirements. Also, this technique is only applicable when your domain is immutable (invalidation is not a requirement), because distributed cache invalidation is incredibly difficult [[3]](#3).
6. Don’t mix cache servers among [bounded contexts](https://martinfowler.com/bliki/BoundedContext.html). Just don’t do it. Keeping cache servers isolated among bounded contexts allows you to gracefully degrade parts of your application in isolation from others. And one misbehaving service can't effect cache peformance for other (unrelated) services. A single large cache cluster is a single point of failure.
7. If your miss rate and evict rate periodically spike, and those spikes are expensive (e.g., associated with high CPU usage on web servers), a good debugging trick is to set a low TTL for any key is expensive to compute and is very sought after. When the key expires or is evicted, you will run into the thundering herds problem easily, and a high TTL will cause you periodic cache grief that you will have lots of fun debugging (said no one, ever). Keeping a low TTL will give you consistent (less than awesome) performance while you work on solving the problem [[4]](#4).

In summary: designing your system around stellar cache performance is almost certainly going to have you paged in the middle of the night. Make sure you test cache failure scenarios, and isolate your system to degrade gracefully.

##### Endnotes

[0] <a name="0"></a> This is a tradeoff. Generally, cache access time is database access/process time plus epsilon, and you should pick epsilon intentionally. For example, it might be okay for cache GETs to suffer from a 1.5x latency if that keeps the database cool under high load.

[1] <a name="1"></a> A common, production hardened proxy is [twemproxy](https://github.com/twitter/twemproxy).

[2] <a name="2"></a> Using [Kubernetes Pods](https://kubernetes.io/docs/concepts/workloads/pods/pod/#motivation-for-pods) or [Nomad task groups](https://www.nomadproject.io/docs/job-specification/group.html).

[3] <a name="3"></a> If multiple replicas of a service have their own side-car cache servers, invalidating any key in your cache requires each replica to know about every other cache server that every other replica uses and to _atomically_ invalidate that key in those cache servers. This is incredibly difficult, just don't do it.

[4] <a name="4"></a> Read about [cache leases](http://dl.acm.org/citation.cfm?id=74870) as used at [Facebook](https://pdfs.semanticscholar.org/e8f9/43e6c9eb33538a127010fd2336c0bca02d88.pdf) (second 3.2.1).

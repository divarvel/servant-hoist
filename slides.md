% Hoist Me Up Before You Lift Lift
% Clément Delafargue
% Haskell Paris Meetup 2018-09-17

-------------------------------------------

## Servant, handlers, natural transformations

-------------------------------------------


## Servant

<details role="note">
Servant is an ensemble of libraries designed
to work with HTTP APIs
</details>

-------------------------------------------

```haskell
type API = "users" :>
     ( Get '[JSON] [User]
  :<|> ReqBody '[JSON] MkUser
         :> Post '[JSON] NoContent
  :<|> Capture "userId" UserId :> 
       ( Get '[JSON] User
    :<|> Delete '[JSON] NoContent
       )
     )
```

<details role="note">
The core is a type-level DSL to model APIs.
You can then provide a server or generate a client.
</details>

-------------------------------------------

```
/
└─ users/
   ├─• GET
   ├─• POST
   └─ <userId>/
      ├─• GET
      └─• DELETE
```

<details role="note">
You can debug an api layout (not exactly this output, but close)
</details>

-------------------------------------------

## Servant Server

<details role="note">
Today I'll talk about servers. servant-server
allows you to get a WAI application based on
the API description (and handlers)
</details>

-------------------------------------------

```haskell
listUsers :: Handler [User]
listUsers = liftIO getAllUsers

createUser :: MkUser -> Handler NoContent
createUser =
    liftIO addUser >=>
      either handleError handleSuccess
  where
    handleError _ = throwError err400
    handleSucces _ = pure NoContent
```

<details role="note">
Handler allows you to do IO, and to
return non-200 http codes with throwError.
It focuses on the data types, rather than HTTP itself
</details>

-------------------------------------------

```haskell
getUser :: UserId -> Handler User
getUser =
  liftIO getUser >=>
    maybe (throwError err404) pure
```

<details role="note">
Parameters extracted from the routes are passed as
function arguments
</details>

-------------------------------------------

```haskell
handlers :: Server API
handlers =
    allUsers :<|> singleUser
  where
    allUsers =
      listUsers :<|> createUser
    singleUser userId =
      getUser userId :<|> deleteUser userId
```

<details role="note">
Server represents a collection of handlers, matching an API type.
It's not a "real" type, but a type family.
</details>

-------------------------------------------

# Server inspection with `:kind!`

```
λ> :kind! Server API
= Handler [User]
  :<|> ((MkUser -> Handler NoContent)
          :<|> (Int -> Handler User
                  :<|> Handler NoContent))
```

<details role="note">
Never forget, `Server API` is not a real type, in case of doubt,
use `:kind!` to know what you're actually dealing with.
kind "evaluates" type families instances
</details>

-------------------------------------------

```haskell
app :: Application
app = serve api handlers
  where
    api :: Proxy API
    api = Proxy
```

<details role="note">
With a server, you can generate a WAI application
(and serve it with warp for instance). all the WAI middlewares
are compatible.
</details>

-------------------------------------------

# Proxy

```haskell




data Proxy a = Proxy
```

<details role="note">
Proxy is is a way to feed a type to a function without an accompanying value.
It's used a lot by servant, and it avoids using undefined when
all we're interested in is the type
</details>

-------------------------------------------

```haskell
{-# LANGUAGE TypeApplications #-}
app :: Application
app = serve @API Proxy handlers
```

<details role="note">
The TypeApplications extension is quite useful in this context,
I'll use it from now on to have terser code
</details>

-------------------------------------------

```haskell

app :: Application
app = serve api handlers
  where
    api :: Proxy API
    api = Proxy
```

-------------------------------------------

```haskell

app :: Application
app = serve (Proxy :: Proxy API) handlers
```

-------------------------------------------

```haskell
{-# LANGUAGE TypeApplications #-}
app :: Application
app = serve @API Proxy handlers
```

--------------------------------------------

## That's all you *need* to use servant

<details role="note">
With that, you're already able to create services
and structure APIs.
</details>

--------------------------------------------

## Dependency injection with Reader

<details role="note">
It's common for our handlers to need a few dependencies:
common config, access to a DB pool, things like that.
A standard way to do that is to use the Reader Monad
</details>

-------------------------------------------

```haskell
-- We need a few things
data Env = Env
  { baseUrl :: Url
  , pool :: DbPool
  }
```

<details role="note">
In our case, we'll need the base url (to construct absolute URLs)
and access to the DB pool
</details>

-------------------------------------------

```haskell
type MyHandler = ReaderT Env Handler

getAllUsers :: DbPool -> IO [User]

listUsers :: MyHandler [User]
listUsers =
  asks pool
    >>= liftIO . getAllUsers
```

<details role="note">
This way we can access the DB pool in our handlers. Since Handler
is already a monad, we use the transformer version of Reader, to
add Reader capabilities to the handler.
</details>

-------------------------------------------

```haskell
type MyServer api = ServerT api MyHandler

handlers :: MyServer API
handlers = ... -- same as before
```

<details role="note">
Note that Server is specialized for Handler, so we need to use the more
general ServerT version.
</details>

-------------------------------------------

# Wiring it all up

```haskell


server :: Env -> Server API
server env =
    hoistServer @API Proxy withEnv handlers
  where
    withEnv :: (MyHandler a -> Handler a)
    withEnv v = runReaderT v env
```

<details role="note">
And now the magic. We wrap everything in hoistServer, and we provide
a function transforming MyHandler into Handler. In our case it's
runReaderT
</details>

-------------------------------------------

```haskell
hoistServer :: HasServer api '[]
            => Proxy api
            -> (forall x. m x -> n x)
            -> ServerT api m
            -> ServerT api n
```

<details role="note">
HasServer is servant's internal type-families-based machinery.
What's important is that we can go from a handler m to handler n.
In our case, m is MyHandler, n is Handler. We can put all our endpoints
in the monads we want as long as we end up with a Handler.
</details>

-------------------------------------------

## `forall x. m x -> n x`

<details role="note">
Note that it does not mention Handler at all. So we can chain as many
transformations as we want, as long as the last one gives us a Handler.
</details>

-------------------------------------------

## Chaining handler transformations

<details role="note">
We'll keep our dependency injection, but we'll add user capabilities
with servant-auth, and we'll add admin-only endpoints
</details>

-------------------------------------------

```haskell
newtype HasAdmin a =
  HasAdmin (MyHandler a)
  deriving (Monad, MonadReader, …)

deleteEverything :: HasAdmin NoContent
deleteEverything =
  liftIO dropDatabase
    >> pure NoContent
```

<details role="note">
HasAdmin wraps around our custom handler. It allows us
to declare endpoints with extended capabilities.
I've omitted all the instances derivation, to let it
delegate to the inner handler.
</details>

-------------------------------------------


```haskell
ensureAdmin :: User
            -> (HasAdmin a -> MyHandler a)
ensureAdmin user (HasAdmin handler)
  | isAdmin user = handler
  | otherwise = throwError err403
```

<details role="note">
Given a user, and an admin-only handler, we can either
delegate to the handler or generate an error.
Note the return type (i've added parens for clarity)
</details>

-------------------------------------------

```haskell
type API =
  Auth '[BasicAuth] User -> UserEndpoints

type UserEndpoints = Regular :<|> Admin
```

<details role="note">
All the endpoints are now protected with basic auth
(the endpoints will take a User parameter)
The protected enpoints are either regular (all users)
or admin-only
</details>

-------------------------------------------

```haskell
server :: Env -> Server API
server env user =
  hoistServer @UserEndpoints
    Proxy
    withEnv
    (userEps user :<|> adminEps user)
```

<details role="note">
The main server is the same, it handles the reader monad.
It also passes the user down to the other servers (it could
also be put in the reader, but I chose not to, for clarity).

Pay special attention to the type annotations (especially the
API vs UserEndpoints). It's not intuitive, and it's easy to be trapped
(I sure was). Discuss it with the audience
</details>

-------------------------------------------

```haskell
adminEps :: User -> MyServer Admin
adminEps user =
  hoistServer @Admin
    Proxy
    (ensureAdmin user)
    deleteEverything
```

<details role="note">
The user endpoints don't change, but for the admin endpoint,
we need to peel out the handler from the HasAdmin wrapper.
We can do so by using the previously defined ensureAdmin.
</details>

-------------------------------------------

```
/ -- MyHandler
├─ users/
┆  ├─• GET
┆  ├─• POST
┆  └─ <userId>/
┆     ├─• GET
┆     └─• DELETE
└─ admin/  -- HasAdmin
   └─ yolo/
      └─• DELETE
```

-------------------------------------------

# Why not middlewares?

-------------------------------------------

## `Application -> Application`

<details role="note">
Not suited for application-level stuff (not visible
in the types). Kludges like vault. It's good protocol-
level stuff (http redirs, etc), but not much more,
and it's for the whole application (or you need to
inspect the requests in the middlewares and that's a
shadow router. not good)
</details>

-------------------------------------------

# Conclusion

- don't thread environment manually,
- use ReaderT

<details role="note">
Most common use case, it comes up fast
in every non-trivial service
</details>

-------------------------------------------

# Conclusion

- define a monad stack for your application

<details role="note">
Try to standardize on a monad stack, avoid
ad-hoc stuff, it'll simplify things and make
maintenance easier
</details>

-------------------------------------------

# Conclusion

- annotate / protect whole API trees with hoistServer

<details role="note">
For application-level concerns, it's way better than
regular middlewares, and it retains type-safety
</details>

-------------------------------------------

# Conclusion

- mind the Proxy type annotations

<details role="note">
That's the most common pitfall, and it's easy to get lost
in servant's type errors
</details>


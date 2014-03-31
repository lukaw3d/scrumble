module Handler.UsersUser where

import Import

import qualified Authorization as Auth

getUsersUserR :: UserId -> Handler Value
getUsersUserR userId = do
  Auth.assert Auth.isAdmin
  userEntity <- runDB $ selectFirst [UserId ==. userId] []
  maybe notFound (return . toJSON . FlatEntity) userEntity

deleteUsersUserR :: UserId -> Handler ()
deleteUsersUserR userId = do
  Auth.assert Auth.isAdmin
  runDB $ delete userId >> return ()
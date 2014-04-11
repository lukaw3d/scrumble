module Handler.Users where

import Import
import Handler.UsersUser (getUsersUserR)
import Validation
import Data.Maybe (isJust, fromJust)

import qualified Authorization as Auth

getUsersR :: Handler Value
getUsersR = do
  Auth.assert Auth.isAdmin
  users :: [Entity User] <- runDB $ selectList [] [] 
  return $ array $ (toJSON . FlatEntity) `fmap` users

postUsersR :: Handler Value
postUsersR = do
  Auth.assert Auth.isAdmin
  user <- requireJsonBody
  userIdMby <- runDB $ insertUnique user 
  runValidationHandler $ 
    ("username", "User with the supplied username already exists") `validate`
      (isJust userIdMby)
  getUsersUserR $ fromJust userIdMby
    
